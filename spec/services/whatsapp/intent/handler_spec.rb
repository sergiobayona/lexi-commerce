require "rails_helper"

RSpec.describe Whatsapp::Intent::Handler do
  let(:business_number) { WaBusinessNumber.create!(phone_number_id: "111", display_phone_number: "15550000000") }
  let(:contact) { WaContact.create!(wa_id: "16505551234", profile_name: "Alice") }
  let(:value) { { "metadata" => { "phone_number_id" => "111" }, "contacts" => [{ "wa_id" => "16505551234" }] } }
  let(:msg) { { "id" => "wamid.1", "type" => "text", "text" => { "body" => "hello" } } }

  subject { described_class.new(value: value, msg: msg) }

  describe "when evaluator detects onboarding greeting with high confidence" do
    it "calls WelcomeResponder directly" do
      result = { label: :onboard_greeting, confidence: 0.9 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))

      # Mock entity resolution
      allow(WaMessage).to receive(:find_by).and_return(nil)
      allow(WaContact).to receive(:find_by).and_return(contact)
      allow(WaBusinessNumber).to receive(:find_by).and_return(business_number)

      responder = instance_double(Whatsapp::Responders::WelcomeResponder)
      expect(Whatsapp::Responders::WelcomeResponder).to receive(:new)
        .with(contact: contact, business_number: business_number)
        .and_return(responder)
      expect(responder).to receive(:call).with(greeting_text: "hello")

      subject.call
    end

    it "logs warning when contact or business_number missing" do
      result = { label: :onboard_greeting, confidence: 0.9 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))

      # Mock missing entities
      allow(WaMessage).to receive(:find_by).and_return(nil)
      allow(WaContact).to receive(:find_by).and_return(nil)
      allow(WaBusinessNumber).to receive(:find_by).and_return(nil)

      expect(Rails.logger).to receive(:warn).with(
        {
          at: "welcome_responder.skipped",
          reason: "missing_contact_or_business_number",
          msg_id: "wamid.1"
        }.to_json
      )

      expect(Whatsapp::Responders::WelcomeResponder).not_to receive(:new)

      subject.call
    end
  end

  describe "when evaluator does not detect onboarding greeting" do
    it "does not call WelcomeResponder" do
      result = { label: :other, confidence: 0.5 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))
      expect(Whatsapp::Responders::WelcomeResponder).not_to receive(:new)

      subject.call
    end

    it "does not call WelcomeResponder when confidence too low" do
      result = { label: :onboard_greeting, confidence: 0.7 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))
      expect(Whatsapp::Responders::WelcomeResponder).not_to receive(:new)

      subject.call
    end
  end

  describe "returns evaluator result and actions" do
    it "returns the result from evaluator with actions taken" do
      result = { label: :onboard_greeting, confidence: 0.9 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))

      # Mock entities to avoid actual responder call
      allow(WaMessage).to receive(:find_by).and_return(nil)
      allow(WaContact).to receive(:find_by).and_return(contact)
      allow(WaBusinessNumber).to receive(:find_by).and_return(business_number)
      allow_any_instance_of(Whatsapp::Responders::WelcomeResponder).to receive(:call)

      expected_response = {
        intent_result: result,
        actions: { welcome_message_sent: true }
      }

      expect(subject.call).to eq(expected_response)
    end

    it "returns false for welcome_message_sent when no greeting intent" do
      result = { label: :other, confidence: 0.5 }

      expect(Whatsapp::Intent::Evaluator).to receive(:new).with(value: value, msg: msg).and_return(double(call: result))

      expected_response = {
        intent_result: result,
        actions: { welcome_message_sent: false }
      }

      expect(subject.call).to eq(expected_response)
    end
  end
end
