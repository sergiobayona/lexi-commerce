# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Controller do
  let(:redis) { Redis.new }
  let(:router) { instance_double(IntentRouter) }
  let(:info_agent) { instance_double(Agents::InfoAgent) }
  let(:commerce_agent) { instance_double(Agents::CommerceAgent) }
  let(:support_agent) { instance_double(Agents::SupportAgent) }
  let(:registry) do
    instance_double(
      AgentRegistry,
      for_lane: info_agent
    )
  end
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
          handoff: nil
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
          handoff: nil
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

      let(:agent_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Switching to commerce..." } }],
          state_patch: {},
          handoff: {
            to_lane: "commerce",
            carry_state: {
              "initiated_from" => "info"
            }
          }
        )
      end

      before do
        allow(router).to receive(:route).and_return(route_decision)
        allow(registry).to receive(:for_lane).with("info").and_return(info_agent)
        allow(info_agent).to receive(:handle).and_return(agent_response)
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
    end

    context "logging" do
      let(:route_decision) do
        RouterDecision.new("commerce", "add_to_cart", 0.92, ["user_intent", "high_confidence"])
      end

      let(:agent_response) do
        Agents::BaseAgent::AgentResponse.new(
          messages: [{ type: "text", text: { body: "Added to cart" } }],
          state_patch: { "cart_items" => [1] },
          handoff: nil
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
        handoff: nil
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
  end
end
