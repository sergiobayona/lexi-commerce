# frozen_string_literal: true

require_relative "../../../lib/agent_config"

module State
  class Controller
    # Result data structure returned from handle_turn
    TurnResult = Data.define(:success, :messages, :state_version, :lane, :error)

    # Configuration defaults
    DEFAULT_SESSION_TTL = 86_400      # 24 hours
    DEFAULT_IDEMPOTENCY_TTL = 3_600   # 1 hour

    MAX_BATON_HOPS = 2

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
      @logger = logger
    end

    # Main entry point for processing a WhatsApp message turn
    # turn: { tenant_id:, wa_id:, message_id:, text:, payload:, timestamp: }
    def handle_turn(turn)
      start_time = Time.now.utc
      session_key = session_key(turn[:tenant_id], turn[:wa_id])

      # 1. Idempotency check
      return duplicate_turn_result if already_processed?(turn[:message_id])

      begin
        # 3. Load or create session
        state, is_new_session = load_or_create_session(turn)

        # 3a. For new sessions, persist initial state before any modifications
        if is_new_session
          @redis.setex(session_key, DEFAULT_SESSION_TTL, state.to_json)
        end

        # 4. Validate state
        @validator.call!(state)

        # 5. Append inbound turn to dialogue history and persist immediately
        # This ensures the user's message is saved even if routing/agent fails
        append_turn_to_dialogue(state, turn)
        save_state!(session_key, state)

        hop = 0
        baton = nil
        route_decision = nil
        agent_response = nil
        accumulated_messages = []  # Bug #8 Fix: Collect all agent messages

        loop do
          previous_lane = route_decision&.lane || state["current_lane"]

          if hop.zero?
            route_decision = @router.route(turn: turn, state: state)
            log_routing(turn, route_decision)
          else
            route_decision = build_baton_decision(baton, route_decision)
            log_baton_reroute(turn, route_decision, baton, hop, previous_lane)
          end

          state["current_lane"] = route_decision.lane

          agent = @registry.for_lane(route_decision.lane)

          agent_response = agent.handle(
            turn: turn,
            state: state,
            intent: route_decision.intent
          )

          # Bug #8 Fix: Accumulate messages from each agent in the baton chain
          accumulated_messages.concat(agent_response.messages || [])

          # Bug #10 Fix: Append agent response to dialogue history
          append_agent_response_to_dialogue(state, agent_response, route_decision.lane)

          complete_patch = build_complete_patch(state: state, agent_response: agent_response)
          apply_complete_patch!(state, complete_patch)

          baton = agent_response.baton
          merge_baton_payload!(state, baton) if baton

          save_state!(session_key, state)

          break unless continue_baton?(baton, hop, state["current_lane"])

          hop += 1
        end

        # 12. Mark message as processed
        mark_processed(turn[:message_id])

        # 13. Log success
        log_turn_success(turn, route_decision, agent_response, Time.now.utc - start_time)

        # 14. Return result with all accumulated messages
        TurnResult.new(
          success: true,
          messages: accumulated_messages,  # Bug #8 Fix: Return all messages from baton chain
          state_version: nil, # No longer tracking versions
          lane: route_decision.lane,
          error: nil
        )

      rescue State::Validator::Invalid => e
        log_validation_error(turn, e)
        reset_corrupted_session(session_key, turn)
        mark_processed(turn[:message_id])
        error_result("Session validation failed: #{e.message}")

      rescue StandardError => e
        log_error(turn, e)
        mark_processed(turn[:message_id])
        error_result("Turn processing failed: #{e.message}")
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
    # Session Lifecycle
    # ============================================

    def load_or_create_session(turn)
      session_key = session_key(turn[:tenant_id], turn[:wa_id])
      json_str = @redis.get(session_key)

      if json_str
        # Hydrate existing session (auto-upcasts if needed)
        state = @builder.from_json(json_str)
        [ state, false ]  # existing session
      else
        # Create new session
        state = @builder.new_session(
          tenant_id: turn[:tenant_id],
          wa_id: turn[:wa_id],
          locale: turn[:locale] || "es-CO",
          timezone: turn[:timezone] || "America/Bogota"
        )
        [ state, true ]  # new session
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
      state["turns"] ||= []
      state["turns"] << {
        "role" => "user",
        "message_id" => turn[:message_id],
        "text" => turn[:text],
        "payload" => turn[:payload],
        "timestamp" => turn[:timestamp] || Time.now.utc.iso8601
      }
      state["last_user_msg_id"] = turn[:message_id]
    end

    # Bug #10 Fix: Append agent response to dialogue history
    def append_agent_response_to_dialogue(state, agent_response, lane)
      state["turns"] ||= []
      state["turns"] << {
        "role" => "assistant",
        "lane" => lane,
        "messages" => agent_response.messages || [],
        "timestamp" => Time.now.utc.iso8601
      }
    end

    # ============================================
    # State Updates
    # ============================================

    def build_complete_patch(state:, agent_response:)
      # Start with dialogue/routing fields that changed
      complete_patch = {
        "turns" => state["turns"],
        "last_user_msg_id" => state["last_user_msg_id"],
        "current_lane" => state["current_lane"]
      }

      # Simple merge agent's flat patch
      complete_patch.merge!(agent_response.state_patch) if agent_response.state_patch

      complete_patch
    end

    def apply_complete_patch!(state, patch)
      # Simple flat merge - no deep merging needed
      state.merge!(patch)
    end

    def save_state!(session_key, state)
      state["updated_at"] = Time.now.utc.iso8601
      @redis.setex(session_key, DEFAULT_SESSION_TTL, state.to_json)
    end

    def continue_baton?(baton, hop, current_lane)
      return false unless baton

      if hop >= MAX_BATON_HOPS
        @logger.info({
          event: "baton_stop",
          reason: "hop_limit",
          hop_count: hop + 1
        }.to_json)
        return false
      end

      unless AgentConfig.valid_lane?(baton.target)
        @logger.warn({
          event: "baton_stop",
          reason: "invalid_lane",
          target: baton.target
        }.to_json)
        return false
      end

      # Prevent same-lane handoffs (agent handing off to itself)
      if baton.target == current_lane
        @logger.warn({
          event: "baton_stop",
          reason: "same_lane_handoff",
          target: baton.target,
          current_lane: current_lane
        }.to_json)
        return false
      end

      true
    end

    def build_baton_decision(baton, previous_decision)
      payload = baton.payload || {}
      lane = baton.target.to_s
      intent = payload_value(payload, :intent) || previous_decision&.intent || "follow_up"
      confidence = payload_value(payload, :confidence)&.to_f || previous_decision&.confidence || 1.0
      reasons = Array(payload_value(payload, :reasons) || [ "baton_handoff" ])

      RouterDecision.new(lane, intent, confidence, reasons)
    end

    def merge_baton_payload!(state, baton)
      payload = baton.payload
      return unless payload.is_a?(Hash)

      carry_state = payload_value(payload, :carry_state)
      state.merge!(carry_state) if carry_state.is_a?(Hash)
    end

    def payload_value(payload, key)
      payload[key] || payload[key.to_s]
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
        baton_target: agent_response.baton&.target,
        duration_ms: (duration_ms * 1000).round(2)
      }.to_json)
    end

    def log_baton_reroute(turn, decision, baton, hop, from_lane)
      @logger.info({
        event: "baton_reroute",
        message_id: turn[:message_id],
        tenant_id: turn[:tenant_id],
        wa_id: turn[:wa_id],
        hop: hop,
        from_lane: from_lane,
        to_lane: decision.lane,
        intent: decision.intent,
        baton_payload_keys: baton.payload&.keys || [],
        reasons: decision.reasons
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
