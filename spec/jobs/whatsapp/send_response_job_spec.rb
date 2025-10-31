# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::SendResponseJob, type: :job do
  let(:wa_contact) { create(:wa_contact, wa_id: "16505551234") }
  let(:wa_business_number) { create(:wa_business_number, phone_number_id: "106540352242922") }
  let(:wa_message) do
    create(:wa_message,
           wa_contact: wa_contact,
           wa_business_number: wa_business_number,
           body_text: "Hola",
           direction: "inbound")
  end

  let(:text_messages) do
    [
      { type: "text", text: { body: "¡Hola! ¿En qué puedo ayudarte?" } }
    ]
  end

  describe "#perform" do
    context "when sending text messages" do
      it "sends messages via WhatsApp API" do
        allow_any_instance_of(described_class).to receive(:send_text!).and_return(
          { "messages" => [{ "id" => "wamid.test123" }] }
        )

        expect_any_instance_of(described_class).to receive(:send_text!).with(
          to: "16505551234",
          body: "¡Hola! ¿En qué puedo ayudarte?",
          business_number: wa_business_number,
          preview_url: false
        )

        described_class.new.perform(wa_message: wa_message, messages: text_messages)
      end

      it "records outbound messages" do
        allow_any_instance_of(described_class).to receive(:send_text!).and_return(
          { "messages" => [{ "id" => "wamid.test123" }] }
        )

        expect {
          described_class.new.perform(wa_message: wa_message, messages: text_messages)
        }.to change { WaMessage.where(direction: "outbound").count }.by(1)

        outbound = WaMessage.where(direction: "outbound").last
        expect(outbound.direction).to eq("outbound")
        expect(outbound.body_text).to eq("¡Hola! ¿En qué puedo ayudarte?")
        expect(outbound.provider_message_id).to eq("wamid.test123")
      end
    end

    context "when messages array is empty" do
      it "does not send any messages" do
        expect_any_instance_of(described_class).not_to receive(:send_text!)

        described_class.new.perform(wa_message: wa_message, messages: [])
      end
    end

    context "when API returns error" do
      it "raises error for job retry" do
        allow_any_instance_of(described_class).to receive(:send_text!).and_raise(
          Whatsapp::Responders::BaseResponder::ApiError.new("API error", status: 500)
        )

        expect {
          described_class.new.perform(wa_message: wa_message, messages: text_messages)
        }.to raise_error(Whatsapp::Responders::BaseResponder::ApiError)
      end
    end

    context "with multiple messages" do
      let(:multiple_messages) do
        [
          { type: "text", text: { body: "Mensaje 1" } },
          { type: "text", text: { body: "Mensaje 2" } }
        ]
      end

      it "sends all messages in sequence" do
        call_count = 0
        allow_any_instance_of(described_class).to receive(:send_text!) do
          call_count += 1
          { "messages" => [{ "id" => "wamid.test#{call_count}" }] }
        end

        expect_any_instance_of(described_class).to receive(:send_text!).twice

        described_class.new.perform(wa_message: wa_message, messages: multiple_messages)

        # Verify unique message IDs were created
        outbound_messages = WaMessage.where(direction: "outbound").order(:id)
        expect(outbound_messages.pluck(:provider_message_id)).to match_array(["wamid.test1", "wamid.test2"])
      end
    end
  end
end
