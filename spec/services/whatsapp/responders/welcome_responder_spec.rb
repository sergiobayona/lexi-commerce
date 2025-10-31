require "rails_helper"

RSpec.describe Whatsapp::Responders::WelcomeResponder do
  let(:business_number) { WaBusinessNumber.create!(phone_number_id: "111", display_phone_number: "15550000000") }
  let(:contact) { WaContact.create!(wa_id: "16505551234", profile_name: "Maria") }

  describe "#call" do
    it "sends Spanish welcome when Spanish greeting" do
      responder = described_class.new(contact: contact, business_number: business_number)

      api_res = { "messages" => [ { "id" => "wamid.out.1" } ] }
      expect(responder).to receive(:send_text!).with(hash_including(to: contact.wa_id, business_number: business_number)).and_return(api_res)

      result = responder.call(greeting_text: "hola")
      expect(result).to be_a(WaMessage)
      expect(result.direction).to eq("outbound")
      expect(result.body_text).to include("¡Hola")
      expect(result.provider_message_id).to eq("wamid.out.1")
    end

    it "sends English welcome when non-Spanish greeting" do
      responder = described_class.new(contact: contact, business_number: business_number)

      api_res = { "messages" => [ { "id" => "wamid.out.2" } ] }
      expect(responder).to receive(:send_text!).with(hash_including(to: contact.wa_id, business_number: business_number)).and_return(api_res)

      result = responder.call(greeting_text: "hello")
      expect(result).to be_a(WaMessage)
      expect(result.body_text).to include("Hello")
      expect(result.provider_message_id).to eq("wamid.out.2")
    end

    it "raises if contact or business_number missing when called" do
      responder_no_contact = described_class.new(contact: nil, business_number: business_number)
      expect {
        responder_no_contact.call(greeting_text: "hello")
      }.to raise_error(ArgumentError, "contact not found")

      responder_no_business = described_class.new(contact: contact, business_number: nil)
      expect {
        responder_no_business.call(greeting_text: "hello")
      }.to raise_error(ArgumentError, "business_number not found")
    end
  end
end
