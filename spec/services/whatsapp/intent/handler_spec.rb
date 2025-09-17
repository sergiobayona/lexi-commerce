require "rails_helper"

RSpec.describe Whatsapp::Intent::Handler do
  let(:value) { double("value") }
  let(:msg) { { "type" => "text", "body" => "hello" } }

  subject { described_class.new(value: value, msg: msg) }

  describe "when evaluator detects onboarding greeting with high confidence" do
    it "calls the WelcomeResponder" do
      result = { label: :onboard_greeting, confidence: 0.9 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))
      responder = instance_double(Whatsapp::Responders::WelcomeResponder)
      expect(Whatsapp::Responders::WelcomeResponder).to receive(:new).with(value, msg).and_return(responder)
      expect(responder).to receive(:call)

      subject.call
    end
  end

  describe "when evaluator does not detect onboarding greeting" do
    it "does not call the WelcomeResponder" do
      result = { label: :other, confidence: 0.5 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))
      expect(Whatsapp::Responders::WelcomeResponder).not_to receive(:new)

      subject.call
    end
  end
end
