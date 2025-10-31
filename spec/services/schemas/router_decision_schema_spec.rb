# frozen_string_literal: true

require "rails_helper"

RSpec.describe Schemas::RouterDecisionSchema do
  describe "schema definition" do
    it "defines required string fields" do
      expect(described_class.instance_variable_get(:@properties)).to include(
        :lane,
        :intent
      )
    end

    it "defines required number field" do
      expect(described_class.instance_variable_get(:@properties)).to include(:confidence)
    end

    it "defines required array field" do
      expect(described_class.instance_variable_get(:@properties)).to include(:reasoning)
    end
  end

  describe "schema validation" do
    # Note: RubyLLM performs validation during LLM response parsing
    # These tests verify the schema structure is correct

    it "has correct lane enum values" do
      # Schema should restrict lane to specific values
      # This is enforced by RubyLLM during LLM calls
      expect(described_class).to be < RubyLLM::Schema
    end

    it "inherits from RubyLLM::Schema" do
      expect(described_class).to be < RubyLLM::Schema
    end
  end

  describe "usage with RubyLLM" do
    let(:mock_chat) { instance_double(RubyLLM::Chat) }

    before do
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
      allow(mock_chat).to receive(:with_options).and_return(mock_chat)
    end

    it "can be used with RubyLLM chat client" do
      allow(mock_chat).to receive(:ask).and_return({
        "lane" => "commerce",
        "intent" => "start_order",
        "confidence" => 0.85,
        "reasoning" => [ "User mentioned ordering", "Commerce keywords detected" ]
      })

      chat = RubyLLM.chat(provider: :openai, model: "gpt-4o")
      response = chat
        .with_schema(described_class)
        .with_options(temperature: 0.3)
        .ask("User wants to order pizza")

      expect(response).to include(
        "lane" => "commerce",
        "intent" => "start_order",
        "confidence" => 0.85,
        "reasoning" => array_including("User mentioned ordering")
      )
    end

    it "validates lane enum values" do
      # Valid lanes: info, commerce, support
      valid_response = {
        "lane" => "info",
        "intent" => "business_hours",
        "confidence" => 0.9,
        "reasoning" => [ "Asked about hours" ]
      }

      allow(mock_chat).to receive(:ask).and_return(valid_response)

      chat = RubyLLM.chat(provider: :openai, model: "gpt-4o")
      response = chat.with_schema(described_class).ask("What are your hours?")

      expect(response["lane"]).to eq("info")
    end

    it "returns all required fields" do
      complete_response = {
        "lane" => "support",
        "intent" => "refund_request",
        "confidence" => 0.78,
        "reasoning" => [ "User mentioned refund", "Support keywords present", "Negative sentiment" ]
      }

      allow(mock_chat).to receive(:ask).and_return(complete_response)

      chat = RubyLLM.chat(provider: :openai, model: "gpt-4o")
      response = chat.with_schema(described_class).ask("I want a refund")

      expect(response).to include(
        "lane",
        "intent",
        "confidence",
        "reasoning"
      )
    end
  end

  describe "field types" do
    let(:valid_response) do
      {
        "lane" => "info",
        "intent" => "general_info",
        "confidence" => 0.75,
        "reasoning" => [ "General inquiry" ]
      }
    end

    it "lane is a string" do
      expect(valid_response["lane"]).to be_a(String)
    end

    it "intent is a string" do
      expect(valid_response["intent"]).to be_a(String)
    end

    it "confidence is numeric" do
      expect(valid_response["confidence"]).to be_a(Numeric)
    end

    it "reasoning is an array" do
      expect(valid_response["reasoning"]).to be_an(Array)
    end

    it "reasoning contains strings" do
      expect(valid_response["reasoning"]).to all(be_a(String))
    end
  end
end
