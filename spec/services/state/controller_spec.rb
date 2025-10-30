# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Controller do
  let(:redis) { Redis.new }
  let(:router) { instance_double(IntentRouter) }
  let(:info_agent) { instance_double(Agents::InfoAgent) }
  let(:commerce_agent) { instance_double(Agents::CommerceAgent) }
  let(:support_agent) { instance_double(Agents::SupportAgent) }
  let(:registry) { instance_double(AgentRegistry) }
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }

  let(:controller) do
    described_class.new(
      redis: redis,
      router: router,
      registry: registry,
      logger: logger
    )
  end

  let(:base_turn) do
    {
      tenant_id: "tenant_123",
      wa_id: "16505551234",
      message_id: "msg_#{SecureRandom.hex(8)}",
      text: "Hello",
      payload: nil,
      timestamp: Time.now.utc.iso8601
    }
  end

  before do
    # Clean Redis before each test
    redis.flushdb
  end

  after do
    # Clean Redis after each test
    redis.flushdb
  end

  describe "#handle_turn" do
    context "with first message (new session)" do
      let(:route_decision) do
        RouterDecision.new("info", "general_info", 0.9, ["new_user"])
      end

      let(:agent_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Hello!" } }],
          state_patch: { "greeted" => true },
          baton: nil
        )
      end

      before do
        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_return(agent_response)
      end

      it "returns success result" do
        result = controller.handle_turn(base_turn)

        puts "Result: #{result.inspect}" if !result.success
        puts "Error: #{result.error}" if result.error

        expect(result.success).to be true
        expect(result.messages).to eq(agent_response.messages)
        expect(result.lane).to eq("info")
        expect(result.error).to be_nil
      end

      it "creates new session via Builder" do
        result = controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        session_json = redis.get(session_key)
        expect(session_json).to be_present

        state = JSON.parse(session_json)
        expect(state["tenant_id"]).to eq("tenant_123")
        expect(state["wa_id"]).to eq("16505551234")
        expect(state["updated_at"]).to be_present
      end

      it "validates state before processing" do
        validator = instance_double(State::Validator)
        allow(validator).to receive(:call!)

        controller_with_validator = described_class.new(
          redis: redis,
          router: router,
          registry: registry,
          validator: validator,
          logger: logger
        )

        controller_with_validator.handle_turn(base_turn)

        expect(validator).to have_received(:call!).at_least(:once)
      end

      it "appends turn to dialogue history" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        turns = state["turns"]
        expect(turns).to be_an(Array)
        expect(turns.size).to be >= 1

        last_turn = turns.last
        expect(last_turn["role"]).to eq("user")
        expect(last_turn["text"]).to eq("Hello")
        expect(last_turn["message_id"]).to eq(base_turn[:message_id])
      end

      it "calls router with turn and state" do
        controller.handle_turn(base_turn)

        expect(router).to have_received(:route) do |args|
          expect(args[:turn]).to be_a(Hash)
          expect(args[:state]).to be_a(Hash)
        end
      end

      it "dispatches to correct agent" do
        controller.handle_turn(base_turn)

        expect(registry).to have_received(:for_lane).with("info")
        expect(info_agent).to have_received(:handle) do |args|
          expect(args[:turn]).to eq(base_turn)
          expect(args[:state]).to be_a(Hash)
          expect(args[:intent]).to eq("general_info")
        end
      end

      it "applies state patch" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        expect(state["greeted"]).to be true
      end

      it "marks message as processed" do
        controller.handle_turn(base_turn)

        idempotency_key = "turn:processed:#{base_turn[:message_id]}"
        expect(redis.exists?(idempotency_key)).to be true
      end

      it "sets TTL on session" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        ttl = redis.ttl(session_key)

        expect(ttl).to be > 0
        expect(ttl).to be <= 86_400
      end
    end

    context "with idempotent turn (duplicate message)" do
      before do
        # Mark message as already processed
        idempotency_key = "turn:processed:#{base_turn[:message_id]}"
        redis.setex(idempotency_key, 3600, "1")
      end

      it "returns success with duplicate error" do
        result = controller.handle_turn(base_turn)

        expect(result.success).to be true
        expect(result.messages).to be_empty
        expect(result.error).to eq("duplicate_turn")
      end

      it "does not call router" do
        allow(router).to receive(:route)

        controller.handle_turn(base_turn)

        expect(router).not_to have_received(:route)
      end

      it "does not call agent" do
        allow(info_agent).to receive(:handle)

        controller.handle_turn(base_turn)

        expect(info_agent).not_to have_received(:handle)
      end
    end

    context "webhook retry scenarios" do
      it "handles retry after successful processing" do
        # Bug #3 Fix: Webhook retries after success should return duplicate_turn
        route_decision = RouterDecision.new("info", "general_info", 0.9, [])
        agent_response = Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Success" } }],
          state_patch: {},
          baton: nil
        )

        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_return(agent_response)

        # First attempt succeeds
        first_result = controller.handle_turn(base_turn)
        expect(first_result.success).to be true
        expect(first_result.messages).not_to be_empty

        # Webhook retry delivers same message again
        retry_result = controller.handle_turn(base_turn)

        expect(retry_result.success).to be true
        expect(retry_result.error).to eq("duplicate_turn")
        expect(retry_result.messages).to be_empty

        # Agent should only be called once (not on retry)
        expect(info_agent).to have_received(:handle).once
      end

      it "handles retry after validation error" do
        # Bug #3 Fix: Webhook retries after validation error should not reset session again
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        corrupted_state = { "tenant_id" => nil }
        redis.set(session_key, corrupted_state.to_json)

        # First attempt fails validation
        first_result = controller.handle_turn(base_turn)
        expect(first_result.success).to be false
        expect(first_result.error).to match(/validation failed/)

        # Session should be reset to fresh state
        state = JSON.parse(redis.get(session_key))
        expect(state["tenant_id"]).to eq("tenant_123")
        first_updated_at = state["updated_at"]

        # Webhook retry delivers same message again
        retry_result = controller.handle_turn(base_turn)

        expect(retry_result.success).to be true
        expect(retry_result.error).to eq("duplicate_turn")

        # Session should NOT be reset again
        state = JSON.parse(redis.get(session_key))
        expect(state["updated_at"]).to eq(first_updated_at)
      end

      it "handles retry after agent error" do
        # Bug #3 Fix: Webhook retries after agent error should not retry the failing agent
        route_decision = RouterDecision.new("info", "general_info", 0.9, [])

        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_raise(StandardError, "Agent crashed")

        # First attempt fails
        first_result = controller.handle_turn(base_turn)
        expect(first_result.success).to be false
        expect(first_result.error).to match(/Turn processing failed/)

        # Webhook retry delivers same message again
        retry_result = controller.handle_turn(base_turn)

        expect(retry_result.success).to be true
        expect(retry_result.error).to eq("duplicate_turn")

        # Agent should only be called once (not on retry)
        expect(info_agent).to have_received(:handle).once
      end
    end

    context "with existing session" do
      let(:existing_state) do
        State::Builder.new.new_session(
          tenant_id: base_turn[:tenant_id],
          wa_id: base_turn[:wa_id]
        )
      end

      let(:route_decision) do
        RouterDecision.new("commerce", "view_cart", 0.85, ["commerce_intent"])
      end

      let(:agent_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Your cart is empty" } }],
          state_patch: { "last_view" => Time.now.utc.iso8601 },
          baton: nil
        )
      end

      before do
        # Store existing session (keep version from Builder, which is CURRENT_VERSION = 3)
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        redis.set(session_key, existing_state.to_json)

        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("commerce").and_return(commerce_agent)
        allow(commerce_agent).to receive(:handle).and_return(agent_response)
      end

      it "loads existing session" do
        result = controller.handle_turn(base_turn)

        expect(result.success).to be true
      end

      it "updates timestamp" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        updated_state = JSON.parse(redis.get(session_key))

        expect(updated_state["updated_at"]).to be_present
      end

      it "preserves existing state fields" do
        existing_state["custom_field"] = "custom_value"
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        redis.set(session_key, existing_state.to_json)

        controller.handle_turn(base_turn)

        updated_state = JSON.parse(redis.get(session_key))
        expect(updated_state["custom_field"]).to eq("custom_value")
      end
    end

    context "with lane handoff" do
      let(:route_decision) do
        RouterDecision.new("info", "start_shopping", 0.9, ["wants_to_shop"])
      end

      let(:info_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Switching to commerce..." } }],
          state_patch: {},
          baton: Agents::BaseAgent::Baton.new("commerce", {
            carry_state: {
              "initiated_from" => "info"
            },
            intent: "view_cart"
          })
        )
      end

      let(:commerce_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Your cart is empty" } }],
          state_patch: { "handled_by" => "commerce" },
          baton: nil
        )
      end

      before do
        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(registry).to receive(:for_lane).with("commerce").and_return(commerce_agent)
        allow(info_agent).to receive(:handle).and_return(info_response)
        allow(commerce_agent).to receive(:handle).and_return(commerce_response)
      end

      it "runs the baton target agent" do
        controller.handle_turn(base_turn)

        expect(info_agent).to have_received(:handle).once
        expect(commerce_agent).to have_received(:handle).once
      end

      it "updates lane in state" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        expect(state["current_lane"]).to eq("commerce")
      end

      it "carries over specified state" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        expect(state["initiated_from"]).to eq("info")
        expect(state["handled_by"]).to eq("commerce")
      end

      it "returns the baton agent response messages" do
        result = controller.handle_turn(base_turn)

        expect(result.messages).to eq(commerce_response.messages)
        expect(result.lane).to eq("commerce")
      end
    end

    context "with validation error" do
      before do
        # Create corrupted state (invalid structure)
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        corrupted_state = { "tenant_id" => nil }
        redis.set(session_key, corrupted_state.to_json)
      end

      it "returns error result" do
        result = controller.handle_turn(base_turn)

        expect(result.success).to be false
        expect(result.error).to match(/validation failed/)
      end

      it "resets corrupted session" do
        controller.handle_turn(base_turn)

        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        # Should be fresh state
        expect(state["tenant_id"]).to eq("tenant_123")
        expect(state["wa_id"]).to eq("16505551234")
      end

      it "logs validation error" do
        controller.handle_turn(base_turn)

        expect(logger).to have_received(:error) do |log_entry|
          parsed = JSON.parse(log_entry)
          expect(parsed["event"]).to eq("validation_error")
        end
      end

      it "marks message as processed to prevent retry storms" do
        # Bug #3 Fix: Validation errors should mark message as processed
        # to prevent webhook retries from repeatedly resetting the session
        controller.handle_turn(base_turn)

        idempotency_key = "turn:processed:#{base_turn[:message_id]}"
        expect(redis.exists?(idempotency_key)).to be true
      end

      it "prevents retry after validation error" do
        # Bug #3 Fix: Second attempt should return duplicate_turn result
        controller.handle_turn(base_turn)

        # Retry the same message
        result = controller.handle_turn(base_turn)

        expect(result.success).to be true
        expect(result.error).to eq("duplicate_turn")
        expect(result.messages).to be_empty
      end
    end

    context "with agent error" do
      let(:route_decision) do
        RouterDecision.new("info", "general_info", 0.9, [])
      end

      before do
        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_raise(StandardError, "Agent crashed")
      end

      it "returns error result" do
        result = controller.handle_turn(base_turn)

        expect(result.success).to be false
        expect(result.error).to match(/Turn processing failed/)
      end

      it "logs error" do
        controller.handle_turn(base_turn)

        expect(logger).to have_received(:error) do |log_entry|
          parsed = JSON.parse(log_entry)
          expect(parsed["event"]).to eq("turn_error")
          expect(parsed["error"]).to match(/Agent crashed/)
        end
      end

      it "marks message as processed to prevent retry storms" do
        # Bug #3 Fix: Agent errors should mark message as processed
        # to prevent webhook retries from repeatedly failing with the same error
        controller.handle_turn(base_turn)

        idempotency_key = "turn:processed:#{base_turn[:message_id]}"
        expect(redis.exists?(idempotency_key)).to be true
      end

      it "prevents retry after agent error" do
        # Bug #3 Fix: Second attempt should return duplicate_turn result
        controller.handle_turn(base_turn)

        # Retry the same message
        result = controller.handle_turn(base_turn)

        expect(result.success).to be true
        expect(result.error).to eq("duplicate_turn")
        expect(result.messages).to be_empty
      end
    end

    context "dialogue preservation on errors" do
      it "preserves dialogue when router fails" do
        # Bug #5 Fix: User's message should be saved even if router throws exception
        allow(router).to receive(:route).and_raise(StandardError, "Router crashed")

        # Attempt to process turn (will fail)
        result = controller.handle_turn(base_turn)

        expect(result.success).to be false
        expect(result.error).to match(/Turn processing failed/)

        # Dialogue should still be persisted
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        expect(state["turns"]).to be_an(Array)
        expect(state["turns"].size).to eq(1)

        last_turn = state["turns"].last
        expect(last_turn["role"]).to eq("user")
        expect(last_turn["text"]).to eq("Hello")
        expect(last_turn["message_id"]).to eq(base_turn[:message_id])
      end

      it "preserves dialogue when agent fails" do
        # Bug #5 Fix: User's message should be saved even if agent throws exception
        route_decision = RouterDecision.new("info", "general_info", 0.9, [])

        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_raise(StandardError, "Agent crashed")

        # Attempt to process turn (will fail)
        result = controller.handle_turn(base_turn)

        expect(result.success).to be false
        expect(result.error).to match(/Turn processing failed/)

        # Dialogue should still be persisted
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))

        expect(state["turns"]).to be_an(Array)
        expect(state["turns"].size).to eq(1)

        last_turn = state["turns"].last
        expect(last_turn["role"]).to eq("user")
        expect(last_turn["text"]).to eq("Hello")
        expect(last_turn["message_id"]).to eq(base_turn[:message_id])
      end

      it "does not duplicate dialogue on successful retry after error" do
        # Bug #5 Fix: After error is fixed, retry should not duplicate dialogue
        route_decision = RouterDecision.new("info", "general_info", 0.9, [])
        agent_response = Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Success" } }],
          state_patch: {},
          baton: nil
        )

        # First attempt: router fails
        allow(router).to receive(:route).and_raise(StandardError, "Router crashed")
        first_result = controller.handle_turn(base_turn)
        expect(first_result.success).to be false

        # Dialogue should be saved
        session_key = "session:#{base_turn[:tenant_id]}:#{base_turn[:wa_id]}"
        state = JSON.parse(redis.get(session_key))
        expect(state["turns"].size).to eq(1)

        # Second attempt: webhook retry with same message (now marked as processed)
        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_return(agent_response)

        retry_result = controller.handle_turn(base_turn)

        # Should return duplicate_turn (message already processed)
        expect(retry_result.success).to be true
        expect(retry_result.error).to eq("duplicate_turn")

        # Dialogue should NOT be duplicated
        state = JSON.parse(redis.get(session_key))
        expect(state["turns"].size).to eq(1)
      end
    end

    context "logging" do
      let(:route_decision) do
        RouterDecision.new("commerce", "add_to_cart", 0.92, ["user_intent", "high_confidence"])
      end

      let(:agent_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Added to cart" } }],
          state_patch: { "cart_items" => [1] },
          baton: nil
        )
      end

      before do
        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("commerce").and_return(commerce_agent)
        allow(commerce_agent).to receive(:handle).and_return(agent_response)
      end

      it "logs routing decision" do
        allow(logger).to receive(:info)

        controller.handle_turn(base_turn)

        # Check that routing was logged
        expect(logger).to have_received(:info).at_least(:once) do |log_entry|
          parsed = JSON.parse(log_entry)
          parsed["event"] == "turn_routed" &&
            parsed["lane"] == "commerce" &&
            parsed["intent"] == "add_to_cart" &&
            parsed["confidence"] == 0.92
        end
      end

      it "logs turn completion" do
        allow(logger).to receive(:info)

        controller.handle_turn(base_turn)

        # Check that completion was logged
        expect(logger).to have_received(:info).at_least(:once) do |log_entry|
          parsed = JSON.parse(log_entry)
          parsed["event"] == "turn_completed" &&
            parsed["lane"] == "commerce" &&
            parsed["messages_count"] == 1
        end
      end
    end
  end

  describe "concurrency safety" do
    it "handles multiple sessions concurrently" do
      turns = 5.times.map do |i|
        {
          tenant_id: "tenant_123",
          wa_id: "wa_#{i}",
          message_id: "msg_#{i}",
          text: "Hello #{i}",
          payload: nil,
          timestamp: Time.now.utc.iso8601
        }
      end

      route_decision = RouterDecision.new("info", "general_info", 0.9, [])
      agent_response = Agents::BaseAgent::AgentResponse.new(
        messages: [{ type: "text", text: { body: "Hi" } }],
        state_patch: {},
        baton: nil
      )

      allow(router).to receive(:route).and_return(route_decision)
      allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
      allow(info_agent).to receive(:handle).and_return(agent_response)

      threads = turns.map do |turn|
        Thread.new { controller.handle_turn(turn) }
      end

      results = threads.map(&:value)

      expect(results.all?(&:success)).to be true
      expect(results.size).to eq(5)
    end

    it "handles concurrent requests for same session without race condition" do
      # Bug #1 Fix: Verifies that concurrent requests for the same session
      # don't cause the race condition where is_new_session check happens
      # after load_or_create_session, potentially causing session loss

      shared_turn = {
        tenant_id: "tenant_123",
        wa_id: "16505551234",
        message_id: nil,  # will be set per thread
        text: "Concurrent message",
        payload: nil,
        timestamp: Time.now.utc.iso8601
      }

      route_decision = RouterDecision.new("info", "general_info", 0.9, [])
      agent_response = Agents::BaseAgent::AgentResponse.new(
        messages: [{ type: "text", text: { body: "Response" } }],
        state_patch: { "message_count" => 1 },
        baton: nil
      )

      allow(router).to receive(:route).and_return(route_decision)
      allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
      allow(info_agent).to receive(:handle).and_return(agent_response)

      # Create 3 concurrent requests for the same session
      threads = 3.times.map do |i|
        Thread.new do
          turn = shared_turn.merge(message_id: "msg_concurrent_#{i}")
          controller.handle_turn(turn)
        end
      end

      results = threads.map(&:value)

      # All requests should succeed
      expect(results.all?(&:success)).to be true

      # Session should exist in Redis
      session_key = "session:#{shared_turn[:tenant_id]}:#{shared_turn[:wa_id]}"
      session_json = redis.get(session_key)
      expect(session_json).to be_present

      # Session should have all dialogue turns
      state = JSON.parse(session_json)
      expect(state["turns"].size).to eq(3)
      expect(state["tenant_id"]).to eq("tenant_123")
      expect(state["wa_id"]).to eq("16505551234")
    end
  end
end
