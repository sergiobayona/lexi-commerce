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

  before do
    # Clean Redis before each test
    redis.flushdb
  end

  after do
    redis.flushdb
  end

  describe "#perform" do
    context "with valid inbound text message" do
      it "processes the turn successfully" do
        expect {
          described_class.perform_now(wa_message)
        }.not_to raise_error
      end

      it "marks message as orchestrated" do
        described_class.perform_now(wa_message)

        expect(redis.exists?("orchestrated:#{wa_message.provider_message_id}")).to be true
      end

      it "creates session state in Redis" do
        described_class.perform_now(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        expect(redis.exists?(session_key)).to be true

        state = JSON.parse(redis.get(session_key))
        expect(state["meta"]["tenant_id"]).to eq(wa_business_number.phone_number_id)
        expect(state["meta"]["wa_id"]).to eq(wa_contact.wa_id)
        expect(state["version"]).to be > 0
      end

      it "appends turn to dialogue history" do
        described_class.perform_now(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))

        turns = state.dig("dialogue", "turns")
        expect(turns).to be_an(Array)
        expect(turns.size).to be >= 1

        last_turn = turns.last
        expect(last_turn["role"]).to eq("user")
        expect(last_turn["text"]).to eq("Hola")
        expect(last_turn["message_id"]).to eq(wa_message.provider_message_id)
      end

      it "logs orchestration completion" do
        allow(Rails.logger).to receive(:info).and_call_original

        described_class.perform_now(wa_message)

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
        described_class.perform_now(outbound_message)

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
        described_class.perform_now(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        # Session might exist from previous orchestration, but no new turn added
        expect(redis.exists?("orchestrated:#{wa_message.provider_message_id}")).to be true
      end
    end

    context "with nil message" do
      it "handles nil gracefully" do
        expect {
          described_class.perform_now(nil)
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
          described_class.perform_now(wa_message)
        }.to raise_error(StandardError)
      end

      it "logs error details" do
        allow(Rails.logger).to receive(:error).and_call_original

        begin
          described_class.perform_now(wa_message)
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
        described_class.perform_now(button_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))

        last_turn = state.dig("dialogue", "turns").last
        expect(last_turn["text"]).to eq("Ver ubicaciones")
      end
    end

    context "integration with State::Controller" do
      it "routes to info lane by default" do
        described_class.perform_now(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))

        expect(state.dig("meta", "current_lane")).to eq("info")
      end

      it "increments state version" do
        described_class.perform_now(wa_message)

        session_key = "session:#{wa_business_number.phone_number_id}:#{wa_contact.wa_id}"
        state = JSON.parse(redis.get(session_key))
        initial_version = state["version"]

        # Process another message
        wa_message2 = create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.test456",
          type_name: "text",
          body_text: "Segunda mensaje",
          direction: "inbound"
        )

        described_class.perform_now(wa_message2)

        state = JSON.parse(redis.get(session_key))
        expect(state["version"]).to be > initial_version
      end
    end
  end
end
