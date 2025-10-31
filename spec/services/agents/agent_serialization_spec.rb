# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Message Serialization", type: :service do
  let(:mock_chat) { instance_double(RubyLLM::Client) }
  let(:mock_response) { instance_double(RubyLLM::Message, content: "Hello! How can I help you?") }
  let(:turn) { { text: "hello", timestamp: Time.now } }
  let(:state) { { "turns" => [], "slots" => {} } }

  shared_examples "properly extracts RubyLLM::Message content" do |agent_class|
    it "#{agent_class} returns string message, not RubyLLM::Message object" do
      agent = agent_class.new

      # Mock the RubyLLM chat to return RubyLLM::Message
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
      allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
      allow(mock_chat).to receive(:on_tool_call).and_yield(double(name: "test", arguments: {}))
      allow(mock_chat).to receive(:ask).and_return(mock_response)

      response = agent.handle(turn: turn, state: state, intent: "general")

      # Verify response structure
      expect(response).to be_a(Agents::AgentResponse)
      expect(response.messages).to be_an(Array)
      expect(response.messages.first).to be_a(Hash)

      # The critical assertion: message body should be a String, not RubyLLM::Message
      message_body = response.messages.first.dig(:text, :body)
      expect(message_body).to be_a(String)
      expect(message_body).not_to be_a(RubyLLM::Message)
      expect(message_body).to eq("Hello! How can I help you?")
    end
  end

  describe "InfoAgent" do
    include_examples "properly extracts RubyLLM::Message content", Agents::InfoAgent
  end

  describe "ProductAgent" do
    include_examples "properly extracts RubyLLM::Message content", Agents::ProductAgent
  end

  describe "OrderStatusAgent" do
    let(:state) { { "turns" => [], "slots" => {}, "order" => {} } }
    include_examples "properly extracts RubyLLM::Message content", Agents::OrderStatusAgent
  end

  describe "SupportAgent" do
    let(:state) { { "turns" => [], "slots" => {}, "support" => {} } }
    include_examples "properly extracts RubyLLM::Message content", Agents::SupportAgent
  end

  describe "CommerceAgent" do
    let(:state) { { "turns" => [], "slots" => {}, "commerce" => {} } }
    include_examples "properly extracts RubyLLM::Message content", Agents::CommerceAgent
  end
end
