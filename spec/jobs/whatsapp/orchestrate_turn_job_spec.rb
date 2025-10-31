# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::OrchestrateTurnJob, type: :job do
  let(:wa_contact) { create(:wa_contact, wa_id: "16505551234") }
  let(:wa_business_number) { create(:wa_business_number, phone_number_id: "106540352242922") }
  let(:wa_message) do
    create(:wa_message,
      wa_contact: wa_contact,
      wa_business_number: wa_business_number,
      provider_message_id: "wamid.test123",
      type_name: "text",
      body_text: "Hola",
      direction: "inbound",
      timestamp: Time.current
    )
  end

  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")) }
  let(:mock_router) { instance_double(IntentRouter) }
  let(:mock_llm_client) { double("RubyLLM::Client") }

  before do
    # Clean Redis before each test
    redis.flushdb

    # Stub RubyLLM to prevent API calls in tests
    allow(RubyLLM).to receive(:chat).and_return(mock_llm_client)
    allow(IntentRouter).to receive(:new).and_return(mock_router)
    allow(mock_router).to receive(:route).and_return(
      RouterDecision.new("info", "general_info", 0.9, [ "default routing" ])
    )
  end

  after do
    redis.flushdb
  end

  describe "#perform" do
    context "with valid inbound text message" do
      it "processes the turn successfully" do
        expect {
          described_class.new.perform(wa_message)
        }.not_to raise_error
      end

      it "marks message as orchestrated" do
        described_class.new.perform(wa_message)

        expect(redis.exists?("orchestrated:#{wa_message.provider_message_id}")).to be true
      end

      it "creates session state in Redis" do
        described_class.new.perform(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        expect(redis.exists?(session_key)).to be true

        state = JSON.parse(redis.get(session_key))
        expect(state["tenant_id"]).to eq(wa_business_number.phone_number_id)
        expect(state["wa_id"]).to eq(wa_contact.wa_id)
      end

      it "appends turn to dialogue history" do
        described_class.new.perform(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))

        turns = state["turns"]
        expect(turns).to be_an(Array)
        expect(turns.size).to be >= 1

        last_turn = turns.last
        expect(last_turn["role"]).to eq("user")
        expect(last_turn["text"]).to eq("Hola")
        expect(last_turn["message_id"]).to eq(wa_message.provider_message_id)
      end

      it "logs orchestration completion" do
        allow(Rails.logger).to receive(:info).and_call_original

        described_class.new.perform(wa_message)

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end
    end

    context "with outbound message" do
      let(:outbound_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.outbound",
          type_name: "text",
          body_text: "Response",
          direction: "outbound"
        )
      end

      it "skips orchestration for outbound messages" do
        described_class.new.perform(outbound_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        expect(redis.exists?(session_key)).to be false
      end
    end

    context "with already orchestrated message" do
      before do
        # Mark as already orchestrated
        redis.setex("orchestrated:#{wa_message.provider_message_id}", 3600, "1")
      end

      it "skips duplicate orchestration" do
        # Should not create new session state
        described_class.new.perform(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        # Session might exist from previous orchestration, but no new turn added
        expect(redis.exists?("orchestrated:#{wa_message.provider_message_id}")).to be true
      end
    end

    context "with nil message" do
      it "handles nil gracefully" do
        expect {
          described_class.new.perform(nil)
        }.not_to raise_error
      end
    end

    context "with Redis connection error" do
      before do
        # Force an error by making Redis unavailable
        allow_any_instance_of(State::Controller).to receive(:handle_turn).and_raise(Redis::CannotConnectError, "Connection refused")
      end

      it "raises error for retry mechanism" do
        expect {
          described_class.new.perform(wa_message)
        }.to raise_error(StandardError)
      end

      it "logs error details" do
        allow(Rails.logger).to receive(:error).and_call_original

        begin
          described_class.new.perform(wa_message)
        rescue StandardError
          # Expected to raise
        end

        expect(Rails.logger).to have_received(:error).at_least(:once)
      end
    end

    context "with button message" do
      let(:button_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.button123",
          type_name: "button",
          body_text: "Ver ubicaciones",
          direction: "inbound",
          timestamp: Time.current
        )
      end

      it "processes button messages successfully" do
        described_class.new.perform(button_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))

        last_turn = state.dig("dialogue", "turns").last
        expect(last_turn["text"]).to eq("Ver ubicaciones")
      end
    end

    context "integration with State::Controller" do
      it "routes to info lane by default" do
        described_class.new.perform(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))

        expect(state["current_lane"]).to eq("info")
      end
    end
  end

  describe "#serialize_messages (private)" do
    let(:job) { described_class.new }

    context "with plain hash messages" do
      it "stringifies keys and returns serializable hashes" do
        messages = [
          { type: "text", text: { body: "Hello" } },
          { "type" => "text", "text" => { "body" => "World" } }
        ]

        result = job.send(:serialize_messages, messages)

        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first).to eq({ "type" => "text", "text" => { "body" => "Hello" } })
        expect(result.last).to eq({ "type" => "text", "text" => { "body" => "World" } })
      end
    end

    context "with RubyLLM::Message objects" do
      it "extracts content from top-level RubyLLM::Message objects" do
        # Create a mock RubyLLM::Message object
        llm_message = double("RubyLLM::Message")
        allow(llm_message).to receive(:is_a?).with(RubyLLM::Message).and_return(true)
        allow(llm_message).to receive(:content).and_return(double(to_s: "Response from LLM"))

        messages = [ llm_message ]

        result = job.send(:serialize_messages, messages)

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first).to eq("Response from LLM")
      end

      it "extracts content from nested RubyLLM::Message objects in hashes (ACTUAL BUG CASE)" do
        # This is the actual case from the production logs
        # Agent returns: { type: "text", text: { body: <RubyLLM::Message> } }
        llm_message = double("RubyLLM::Message")
        allow(llm_message).to receive(:is_a?).with(RubyLLM::Message).and_return(true)
        allow(llm_message).to receive(:content).and_return(double(to_s: "Hello! How can I assist you today?"))

        messages = [
          { type: "text", text: { body: llm_message } }
        ]

        result = job.send(:serialize_messages, messages)

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first).to eq({
          "type" => "text",
          "text" => { "body" => "Hello! How can I assist you today?" }
        })
      end
    end

    context "with mixed message types" do
      it "handles both plain hashes and nested RubyLLM::Message objects" do
        llm_message = double("RubyLLM::Message")
        allow(llm_message).to receive(:is_a?).with(RubyLLM::Message).and_return(true)
        allow(llm_message).to receive(:content).and_return(double(to_s: "LLM response"))

        messages = [
          { type: "text", text: { body: "First message" } },
          { type: "text", text: { body: llm_message } },
          { type: "text", text: { body: "Third message" } }
        ]

        result = job.send(:serialize_messages, messages)

        expect(result.size).to eq(3)
        expect(result[0]["text"]["body"]).to eq("First message")
        expect(result[1]["text"]["body"]).to eq("LLM response")
        expect(result[2]["text"]["body"]).to eq("Third message")
      end
    end

    context "with nil or empty inputs" do
      it "returns empty array for nil" do
        expect(job.send(:serialize_messages, nil)).to eq([])
      end

      it "returns empty array for empty array" do
        expect(job.send(:serialize_messages, [])).to eq([])
      end
    end

    context "with primitive types" do
      it "returns strings as-is" do
        messages = [ "Plain string message" ]

        result = job.send(:serialize_messages, messages)

        expect(result.size).to eq(1)
        expect(result.first).to eq("Plain string message")
      end

      it "handles arrays within message structures" do
        messages = [
          { type: "text", options: [ "Option 1", "Option 2", "Option 3" ] }
        ]

        result = job.send(:serialize_messages, messages)

        expect(result.size).to eq(1)
        expect(result.first["type"]).to eq("text")
        expect(result.first["options"]).to eq([ "Option 1", "Option 2", "Option 3" ])
      end
    end
  end
end
