# frozen_string_literal: true

require "rails_helper"
require_relative "../../app/services/intent_router"

RSpec.describe IntentRouter do
  let(:router) { described_class.new }
  let(:turn) do
    {
      text: "What are your business hours?",
      payload: nil,
      timestamp: Time.now.utc.iso8601,
      tenant_id: "tenant_123",
      wa_id: "16505551234",
      message_id: "msg_001"
    }
  end
  let(:state) do
    {
      "tenant_id" => "tenant_123",
      "wa_id" => "16505551234",
      "locale" => "en",
      "current_lane" => nil,
      "location_id" => "loc_001",
      "fulfillment" => "delivery",
      "address" => nil,
      "commerce_state" => nil,
      "cart_items" => []
    }
  end

  describe "#route" do
    context "with valid configuration" do
      it "returns a RouterDecision" do
        # Mock LLM response
        mock_response = double(
          content: {
            "lane" => "info",
            "intent" => "business_hours",
            "confidence" => 0.95,
            "reasoning" => [ "User asking about hours", "Keywords: business hours" ]
          }
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mock_response)

        result = router.route(turn: turn, state: state)

        expect(result).to be_a(RouterDecision)
        expect(result.lane).to eq("info")
        expect(result.intent).to eq("business_hours")
        expect(result.confidence).to eq(0.95)
        expect(result.reasons).to include("User asking about hours")
      end
    end

    context "when configuration error occurs" do
      # Bug #15 Fix: Test that configuration errors are caught and handled gracefully
      before do
        # Mock RoutingConfig to raise ConfigurationError
        allow(RoutingConfig).to receive(:system_prompt).and_raise(
          RoutingConfig::ConfigurationError.new("Invalid Liquid template in system_prompt: missing closing tag")
        )
      end

      it "returns fallback RouterDecision with config error" do
        result = router.route(turn: turn, state: state)

        expect(result).to be_a(RouterDecision)
        expect(result.lane).to eq("info")
        expect(result.intent).to eq("general_info")
        expect(result.confidence).to eq(0.1)
        expect(result.reasons.first).to include("config_error")
        expect(result.reasons.first).to include("Invalid Liquid template")
      end

      it "logs the configuration error" do
        expect(Rails.logger).to receive(:error).with(/Routing configuration error/)

        router.route(turn: turn, state: state)
      end

      it "does not call LLM when configuration fails" do
        expect_any_instance_of(RubyLLM::Chat).not_to receive(:ask)

        router.route(turn: turn, state: state)
      end
    end

    context "when LLM call fails" do
      before do
        # Mock LLM to raise an error
        allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_raise(
          StandardError.new("Network timeout")
        )
      end

      it "returns fallback RouterDecision" do
        result = router.route(turn: turn, state: state)

        expect(result).to be_a(RouterDecision)
        expect(result.lane).to eq("info")
        expect(result.intent).to eq("general_info")
        expect(result.confidence).to eq(0.3)
        expect(result.reasons.first).to include("router_error")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Router error/)

        router.route(turn: turn, state: state)
      end

      it "does not expose full backtrace in reasons" do
        result = router.route(turn: turn, state: state)

        # Bug #15 Fix: Backtrace should not be included
        expect(result.reasons.first).not_to include("/Users/")
        expect(result.reasons.first).not_to include(".rbenv")
        expect(result.reasons.first).to eq("router_error: StandardError")
      end
    end

    context "confidence clamping" do
      it "clamps confidence values above 1.0" do
        mock_response = double(
          content: {
            "lane" => "info",
            "intent" => "general",
            "confidence" => 5.7,  # Invalid, should be clamped
            "reasoning" => [ "test" ]
          }
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mock_response)

        result = router.route(turn: turn, state: state)
        expect(result.confidence).to eq(1.0)
      end

      it "clamps confidence values below 0.0" do
        mock_response = double(
          content: {
            "lane" => "info",
            "intent" => "general",
            "confidence" => -0.5,  # Invalid, should be clamped
            "reasoning" => [ "test" ]
          }
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mock_response)

        result = router.route(turn: turn, state: state)
        expect(result.confidence).to eq(0.0)
      end
    end

    context "reasoning array handling" do
      it "handles nil reasoning" do
        mock_response = double(
          content: {
            "lane" => "info",
            "intent" => "general",
            "confidence" => 0.8,
            "reasoning" => nil
          }
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mock_response)

        result = router.route(turn: turn, state: state)
        expect(result.reasons).to eq([])
      end

      it "limits reasoning to 5 items" do
        mock_response = double(
          content: {
            "lane" => "info",
            "intent" => "general",
            "confidence" => 0.8,
            "reasoning" => [ "1", "2", "3", "4", "5", "6", "7" ]
          }
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_return(mock_response)

        result = router.route(turn: turn, state: state)
        expect(result.reasons.size).to eq(5)
      end
    end
  end
end
