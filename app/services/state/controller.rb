# frozen_string_literal: true

require_relative "../../../lib/agent_config"

module State
  class Controller
    # Result data structure returned from handle_turn
    TurnResult = Data.define(:success, :messages, :state_version, :lane, :error)

    # Configuration defaults
    DEFAULT_SESSION_TTL = 86_400      # 24 hours
    DEFAULT_IDEMPOTENCY_TTL = 3_600   # 1 hour
    DEFAULT_LOCK_TTL = 30             # 30 seconds
    MAX_LOCK_WAIT = 5                 # seconds
    LOCK_RETRY_INTERVAL = 0.1         # seconds

    def initialize(
      redis:,
      router:,
      registry:,
      builder: State::Builder.new,
      validator: State::Validator.new,
      logger: Rails.logger
    )
      @redis = redis
      @router = router
      @registry = registry
      @builder = builder
      @validator = validator
      @patcher = State::Patcher.new(redis)
      @logger = logger
    end

    # Main entry point for processing a WhatsApp message turn
    # turn: { tenant_id:, wa_id:, message_id:, text:, payload:, timestamp: }
    def handle_turn(turn)
      start_time = Time.now.utc
      session_key = session_key(turn[:tenant_id], turn[:wa_id])

      # 1. Idempotency check
      return duplicate_turn_result if already_processed?(turn[:message_id])

      # 2. Acquire session lock
      unless acquire_lock!(session_key)
        return busy_result("Failed to acquire session lock")
      end

      begin
        # 3. Load or create session
        state = load_or_create_session(turn)
        is_new_session = @redis.get(session_key).nil?

        # 3a. For new sessions, persist initial state before any modifications
        if is_new_session
          @redis.setex(session_key, DEFAULT_SESSION_TTL, state.to_json)
        end

        # 4. Validate state
        @validator.call!(state)

        # 5. Append inbound turn to dialogue history (in-memory only for routing)
        append_turn_to_dialogue(state, turn)

        # 6. Route to determine lane and intent
        route_decision = @router.route(turn: turn, state: state)
        log_routing(turn, route_decision)

        # 7. Update sticky lane metadata
        @router.update_sticky!(
          state: state,
          lane: route_decision.lane,
          seconds: route_decision.sticky_seconds
        )

        # 8. Get agent for the lane
        agent = @registry.for_lane(route_decision.lane)

        # 9. Invoke agent
        agent_response = agent.handle(
          turn: turn,
          state: state,
          intent: route_decision.intent
        )

        # 10. Build complete patch including dialogue update and sticky routing metadata
        complete_patch = build_complete_patch(state: state, agent_response: agent_response)

        # 11. Apply complete state patch with optimistic locking
        patch_success = apply_state_patch(
          session_key: session_key,
          current_state: state,
          patch: complete_patch
        )

        unless patch_success
          # Retry once on conflict - reload state and rebuild complete patch
          state = load_or_create_session(turn)

          # Re-append turn to fresh dialogue
          append_turn_to_dialogue(state, turn)

          # Re-apply sticky routing metadata
          @router.update_sticky!(
            state: state,
            lane: route_decision.lane,
            seconds: route_decision.sticky_seconds
          )

          # Rebuild complete patch with refreshed state
          complete_patch = build_complete_patch(state: state, agent_response: agent_response)

          patch_success = apply_state_patch(
            session_key: session_key,
            current_state: state,
            patch: complete_patch
          )

          return error_result("State patch conflict after retry") unless patch_success
        end

        # 11. Handle lane handoff if requested
        if agent_response.handoff
          # Reload state to get updated version after patch
          state = load_or_create_session(turn)
          handle_lane_handoff(
            session_key: session_key,
            state: state,
            handoff: agent_response.handoff
          )
        end

        # 12. Mark message as processed
        mark_processed(turn[:message_id])

        # 13. Log success
        log_turn_success(turn, route_decision, agent_response, Time.now.utc - start_time)

        # 14. Return result
        TurnResult.new(
          success: true,
          messages: agent_response.messages,
          state_version: state["version"] + 1,
          lane: route_decision.lane,
          error: nil
        )

      rescue State::Validator::Invalid => e
        log_validation_error(turn, e)
        reset_corrupted_session(session_key, turn)
        error_result("Session validation failed: #{e.message}")

      rescue StandardError => e
        log_error(turn, e)
        error_result("Turn processing failed: #{e.message}")

      ensure
        release_lock!(session_key)
      end
    end

    private

    # ============================================
    # Key Generation
    # ============================================

    def session_key(tenant_id, wa_id)
      "session:#{tenant_id}:#{wa_id}"
    end

    def idempotency_key(message_id)
      "turn:processed:#{message_id}"
    end

    def lock_key(session_key)
      "#{session_key}:lock"
    end

    # ============================================
    # Idempotency
    # ============================================

    def already_processed?(message_id)
      @redis.exists?(idempotency_key(message_id))
    end

    def mark_processed(message_id)
      @redis.setex(idempotency_key(message_id), DEFAULT_IDEMPOTENCY_TTL, "1")
    end

    # ============================================
    # Distributed Locking
    # ============================================

    def acquire_lock!(session_key)
      lock_id = "lock:#{SecureRandom.uuid}"
      deadline = Time.now.utc + MAX_LOCK_WAIT

      while Time.now.utc < deadline
        # Try to acquire lock with NX (only set if not exists) and EX (expiry)
        acquired = @redis.set(
          lock_key(session_key),
          lock_id,
          nx: true,
          ex: DEFAULT_LOCK_TTL
        )

        if acquired
          # Store lock_id in thread-local storage for release verification
          Thread.current[:session_lock_id] = lock_id
          return true
        end

        sleep(LOCK_RETRY_INTERVAL)
      end

      false
    end

    def release_lock!(session_key)
      lock_id = Thread.current[:session_lock_id]
      return unless lock_id

      # Only delete if we own the lock (prevent releasing someone else's lock)
      lua_script = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      @redis.eval(lua_script, keys: [ lock_key(session_key) ], argv: [ lock_id ])
      Thread.current[:session_lock_id] = nil
    end

    # ============================================
    # Session Lifecycle
    # ============================================

    def load_or_create_session(turn)
      session_key = session_key(turn[:tenant_id], turn[:wa_id])
      json_str = @redis.get(session_key)

      if json_str
        # Hydrate existing session (auto-upcasts if needed)
        @builder.from_json(json_str)
      else
        # Create new session
        @builder.new_session(
          tenant_id: turn[:tenant_id],
          wa_id: turn[:wa_id],
          locale: turn[:locale] || "es-CO",
          timezone: turn[:timezone] || "America/Bogota"
        )
      end
    end

    def reset_corrupted_session(session_key, turn)
      @logger.warn("Resetting corrupted session: #{session_key}")

      # Create fresh session
      fresh_state = @builder.new_session(
        tenant_id: turn[:tenant_id],
        wa_id: turn[:wa_id],
        locale: turn[:locale] || "es-CO",
        timezone: turn[:timezone] || "America/Bogota"
      )

      # Persist immediately
      @redis.setex(session_key, DEFAULT_SESSION_TTL, fresh_state.to_json)
    end

    # ============================================
    # Dialogue Management
    # ============================================

    def append_turn_to_dialogue(state, turn)
      state["dialogue"] ||= { "turns" => [] }
      state["dialogue"]["turns"] << {
        "role" => "user",
        "message_id" => turn[:message_id],
        "text" => turn[:text],
        "payload" => turn[:payload],
        "timestamp" => turn[:timestamp] || Time.now.utc.iso8601
      }
      state["dialogue"]["last_user_msg_id"] = turn[:message_id]
    end

    # ============================================
    # State Updates
    # ============================================

    def build_complete_patch(state:, agent_response:)
      complete_patch = {
        "dialogue" => state["dialogue"],
        "meta" => state["meta"]
      }

      # Deep merge agent's state patch (if any) to preserve existing keys
      if agent_response.state_patch
        agent_response.state_patch.each do |key, value|
          if complete_patch[key].is_a?(Hash) && value.is_a?(Hash)
            complete_patch[key] = complete_patch[key].merge(value)
          else
            complete_patch[key] = value
          end
        end
      end

      complete_patch
    end

    def apply_state_patch(session_key:, current_state:, patch:)
      # Always save state to persist dialogue updates and increment version
      # Pass empty hash if no agent patch
      @patcher.patch!(
        key: session_key,
        expected_version: current_state["version"],
        patch: patch || {},
        ttl_seconds: DEFAULT_SESSION_TTL
      )
    end

    def handle_lane_handoff(session_key:, state:, handoff:)
      target_lane = handoff[:to_lane]
      return unless AgentConfig.valid_lane?(target_lane)

      handoff_patch = {
        "meta" => {
          "current_lane" => target_lane,
          "sticky_until" => nil # Clear stickiness on handoff
        }
      }

      # Optionally carry over specific state
      if handoff[:carry_state]
        handoff_patch.merge!(handoff[:carry_state])
      end

      apply_state_patch(
        session_key: session_key,
        current_state: state,
        patch: handoff_patch
      )
    end

    # ============================================
    # Result Builders
    # ============================================

    def duplicate_turn_result
      TurnResult.new(
        success: true,
        messages: [],
        state_version: nil,
        lane: nil,
        error: "duplicate_turn"
      )
    end

    def busy_result(message)
      TurnResult.new(
        success: false,
        messages: [],
        state_version: nil,
        lane: nil,
        error: message
      )
    end

    def error_result(message)
      TurnResult.new(
        success: false,
        messages: [],
        state_version: nil,
        lane: nil,
        error: message
      )
    end

    # ============================================
    # Observability
    # ============================================

    def log_routing(turn, decision)
      @logger.info({
        event: "turn_routed",
        message_id: turn[:message_id],
        tenant_id: turn[:tenant_id],
        wa_id: turn[:wa_id],
        lane: decision.lane,
        intent: decision.intent,
        confidence: decision.confidence,
        sticky_seconds: decision.sticky_seconds,
        reasons: decision.reasons
      }.to_json)
    end

    def log_turn_success(turn, decision, agent_response, duration_ms)
      @logger.info({
        event: "turn_completed",
        message_id: turn[:message_id],
        tenant_id: turn[:tenant_id],
        wa_id: turn[:wa_id],
        lane: decision.lane,
        intent: decision.intent,
        messages_count: agent_response.messages&.size || 0,
        state_patch_keys: agent_response.state_patch&.keys || [],
        handoff: agent_response.handoff&.dig(:to_lane),
        duration_ms: (duration_ms * 1000).round(2)
      }.to_json)
    end

    def log_validation_error(turn, error)
      @logger.error({
        event: "validation_error",
        message_id: turn[:message_id],
        tenant_id: turn[:tenant_id],
        wa_id: turn[:wa_id],
        error: error.message,
        error_class: error.class.name
      }.to_json)
    end

    def log_error(turn, error)
      @logger.error({
        event: "turn_error",
        message_id: turn[:message_id],
        tenant_id: turn[:tenant_id],
        wa_id: turn[:wa_id],
        error: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.first(5)
      }.to_json)
    end
  end
end
