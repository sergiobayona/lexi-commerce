# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::InfoAgent do
  let(:mock_chat) { instance_double(RubyLLM::Chat) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tools).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_call).and_return(mock_chat)
    allow(mock_chat).to receive(:respond_to?).and_call_original
    allow(mock_chat).to receive(:respond_to?).with(:with_tools).and_return(true)
  end

  describe "#initialize" do
    subject(:agent) { described_class.new }

    before do
      allow(mock_chat).to receive(:respond_to?).with(:on_tool_result).and_return(true)
      allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)
    end

    it "initializes with default model and chat instance" do
      expect(agent).to be_a(Agents::InfoAgent)
      expect(agent.chat).to eq(mock_chat)
    end

    it "accepts custom model parameter" do
      allow(mock_chat).to receive(:respond_to?).with(:on_tool_result).and_return(true)
      allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)

      custom_agent = described_class.new(model: "gpt-4")
      expect(custom_agent).to be_a(Agents::InfoAgent)
    end

    it "exposes tool specs for general info tools" do
      spec_ids = agent.send(:tool_specs, {}).map(&:id)
      expect(spec_ids).to match_array(%i[business_hours locations general_faq])
    end
  end

  describe "#ask" do
    let(:agent) do
      allow(mock_chat).to receive(:respond_to?).with(:on_tool_result).and_return(true)
      allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)
      described_class.new
    end

    it "processes questions through chat" do
      allow(mock_chat).to receive(:ask).with("What are your business hours?")
                                       .and_return(double(content: "We're open Monday-Friday 11 AM - 10 PM"))

      response = agent.ask("What are your business hours?")
      expect(response).to eq("We're open Monday-Friday 11 AM - 10 PM")
    end

    it "logs questions and responses" do
      allow(mock_chat).to receive(:ask).and_return(double(content: "Response"))

      expect(Rails.logger).to receive(:info).with("[InfoAgent] Processing question: Test question")
      expect(Rails.logger).to receive(:info).with("[InfoAgent] Response: Response")

      agent.ask("Test question")
    end

    context "when chat raises an error" do
      it "handles errors gracefully" do
        allow(mock_chat).to receive(:ask).and_raise(StandardError.new("API Error"))

        expect(Rails.logger).to receive(:error).with("[InfoAgent] Error processing question: API Error")
        expect(Rails.logger).to receive(:error).with(anything) # backtrace

        response = agent.ask("Question")
        expect(response).to include("Unable to process your request")
      end
    end
  end

  describe "#system_instructions" do
    let(:agent) do
      allow(mock_chat).to receive(:respond_to?).with(:on_tool_result).and_return(true)
      allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)
      described_class.new
    end

    it "includes tool descriptions" do
      instructions = agent.send(:system_instructions)

      expect(instructions).to include("BusinessHours")
      expect(instructions).to include("Locations")
      expect(instructions).to include("GeneralFaq")
    end

    it "includes usage guidelines" do
      instructions = agent.send(:system_instructions)

      expect(instructions).to include("friendly")
      expect(instructions).to include("professional")
      expect(instructions).to include("accurate")
    end

    it "provides tool-specific guidance" do
      instructions = agent.send(:system_instructions)

      expect(instructions).to include("'day' parameter")
      expect(instructions).to include("'latitude'")
      expect(instructions).to include("category")
    end
  end
end
