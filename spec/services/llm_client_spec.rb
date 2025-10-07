# frozen_string_literal: true

require "rails_helper"

RSpec.describe LLMClient do
  let(:system_prompt) { "You are a routing agent" }
  let(:messages) do
    [
      { role: "system", content: system_prompt },
      { role: "user", content: "I want to order pizza" }
    ]
  end

  describe "#initialize" do
    context "when LLM routing is enabled" do
      before do
        stub_const("LLMClient::ENABLED", true)
        stub_const("LLMClient::PROVIDER", :openai)
        stub_const("LLMClient::MODEL", "gpt-4o-mini")
      end

      it "initializes RubyLLM chat client" do
        expect(RubyLLM).to receive(:chat).with(provider: :openai, model: "gpt-4o-mini")
        described_class.new
      end
    end

    context "when LLM routing is disabled" do
      before do
        stub_const("LLMClient::ENABLED", false)
      end

      it "does not initialize RubyLLM client" do
        expect(RubyLLM).not_to receive(:chat)
        described_class.new
      end
    end
  end

  describe "#call" do
    subject(:client) { described_class.new }

    context "when LLM routing is disabled" do
      before do
        stub_const("LLMClient::ENABLED", false)
      end

      it "returns fallback response" do
        result = client.call(system: system_prompt, messages: messages)

        expect(result).to eq({
          "arguments" => {
            "lane" => "info",
            "intent" => "general_info",
            "confidence" => 0.5,
            "sticky_seconds" => 60,
            "reasoning" => [ "LLM routing disabled or failed, using fallback" ]
          }
        })
      end

      it "does not call RubyLLM" do
        expect_any_instance_of(RubyLLM::Chat).not_to receive(:ask)
        client.call(system: system_prompt, messages: messages)
      end
    end

    context "when LLM routing is enabled" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:llm_response) do
        {
          "lane" => "commerce",
          "intent" => "start_order",
          "confidence" => 0.85,
          "sticky_seconds" => 120,
          "reasoning" => [ "User wants to order", "Commerce keywords detected" ]
        }
      end

      before do
        stub_const("LLMClient::ENABLED", true)
        stub_const("LLMClient::PROVIDER", :openai)
        stub_const("LLMClient::MODEL", "gpt-4o-mini")
        stub_const("LLMClient::TEMPERATURE", 0.3)

        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
        allow(mock_chat).to receive(:with_options).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(llm_response)
      end

      it "calls RubyLLM with schema" do
        expect(mock_chat).to receive(:with_schema).with(Schemas::RouterDecisionSchema)
        client.call(system: system_prompt, messages: messages)
      end

      it "sets temperature option" do
        expect(mock_chat).to receive(:with_options).with(hash_including(temperature: 0.3))
        client.call(system: system_prompt, messages: messages)
      end

      it "sets timeout option" do
        expect(mock_chat).to receive(:with_options).with(hash_including(timeout: 0.9))
        client.call(system: system_prompt, messages: messages, timeout: 0.9)
      end

      it "builds prompt from system and user messages" do
        expected_prompt = "#{system_prompt}\n\nI want to order pizza"
        expect(mock_chat).to receive(:ask).with(expected_prompt)
        client.call(system: system_prompt, messages: messages)
      end

      it "returns structured response" do
        result = client.call(system: system_prompt, messages: messages)

        expect(result).to eq({
          "arguments" => {
            "lane" => "commerce",
            "intent" => "start_order",
            "confidence" => 0.85,
            "sticky_seconds" => 120,
            "reasoning" => [ "User wants to order", "Commerce keywords detected" ]
          }
        })
      end

      it "filters only user messages for prompt" do
        mixed_messages = [
          { role: "system", content: "System message" },
          { role: "user", content: "First user message" },
          { role: "assistant", content: "Assistant message" },
          { role: "user", content: "Second user message" }
        ]

        expected_prompt = "#{system_prompt}\n\nFirst user message\nSecond user message"
        expect(mock_chat).to receive(:ask).with(expected_prompt)
        client.call(system: system_prompt, messages: mixed_messages)
      end
    end

    context "when LLM call fails" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }

      before do
        stub_const("LLMClient::ENABLED", true)
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
        allow(mock_chat).to receive(:with_options).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_raise(StandardError.new("API error"))
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/LLM routing failed: StandardError - API error/)
        client.call(system: system_prompt, messages: messages)
      end

      it "returns fallback response" do
        result = client.call(system: system_prompt, messages: messages)

        expect(result).to eq({
          "arguments" => {
            "lane" => "info",
            "intent" => "general_info",
            "confidence" => 0.5,
            "sticky_seconds" => 60,
            "reasoning" => [ "LLM routing disabled or failed, using fallback" ]
          }
        })
      end

      it "does not raise error" do
        expect { client.call(system: system_prompt, messages: messages) }.not_to raise_error
      end
    end
  end

  describe "configuration constants" do
    it "has default provider" do
      expect(described_class::PROVIDER).to be_a(Symbol)
    end

    it "has default model" do
      expect(described_class::MODEL).to be_a(String)
    end

    it "has default timeout" do
      expect(described_class::TIMEOUT).to be_a(Float)
    end

    it "has default temperature" do
      expect(described_class::TEMPERATURE).to be_a(Float)
    end

    it "has enabled flag" do
      expect([ true, false ]).to include(described_class::ENABLED)
    end
  end
end
