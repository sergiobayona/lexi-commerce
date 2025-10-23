# spec/jobs/whatsapp/process_message_job_spec.rb
require "rails_helper"

RSpec.describe Whatsapp::ProcessMessageJob, type: :job do
  let(:business_number) { WaBusinessNumber.create!(phone_number_id: "111", display_phone_number: "15550000000") }
  let(:contact) { WaContact.create!(wa_id: "16505551234", profile_name: "Alice") }

  let(:value) do
    { "messaging_product" => "whatsapp",
      "metadata" => { "display_phone_number" => "15550000000", "phone_number_id" => "111" },
      "contacts" => [ { "wa_id" => "16505551234", "profile" => { "name" => "Alice" } } ]
    }
  end

  describe "#perform" do
    before do
      business_number
      contact
    end

    it "calls TextProcessor for text messages" do
      msg = { "id" => "wamid.1", "timestamp" => "1749416383", "type" => "text", "text" => { "body" => "hi" } }
      expect(Whatsapp::Processors::TextProcessor)
        .to receive(:new).with(value, msg).and_call_original
      expect_any_instance_of(Whatsapp::Processors::TextProcessor)
        .to receive(:call)

      described_class.perform_now(value, msg)
    end

    it "calls AudioProcessor for audio messages" do
      msg = { "id" => "wamid.2", "timestamp" => "1749416383", "type" => "audio", "audio" => { "id" => "media.9", "sha256" => "abc", "mime_type" => "audio/ogg" } }
      expect(Whatsapp::Processors::AudioProcessor)
        .to receive(:new).with(value, msg).and_call_original
      expect_any_instance_of(Whatsapp::Processors::AudioProcessor)
        .to receive(:call)

      described_class.perform_now(value, msg)
    end

    context "with audio messages and intent handling" do
      let(:audio_msg) do
        { "id" => "wamid.audio123", "timestamp" => "1749416383", "type" => "audio",
          "audio" => { "id" => "media.audio", "sha256" => "abc123", "mime_type" => "audio/ogg", "voice" => true } }
      end

      before do
        # Allow processors to complete normally
        allow_any_instance_of(Whatsapp::Processors::AudioProcessor).to receive(:call)
      end

      context "when audio message/media records are missing" do
        it "handles missing wa_message gracefully" do
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }

          # No message record created, so emit_audio_received_event should return early
          expect(Stream::Publisher).not_to receive(:new)

          expect { described_class.perform_now(value, audio_msg) }.not_to raise_error
        end

        it "handles missing wa_media gracefully" do
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }

          # Create message but no media
          WaMessage.create!(
            provider_message_id: "wamid.audio123",
            direction: "inbound",
            wa_contact: contact,
            wa_business_number: business_number,
            type_name: "audio",
            timestamp: Time.at(1749416383).utc,
            status: "received"
          )

          expect(Stream::Publisher).not_to receive(:new)

          expect { described_class.perform_now(value, audio_msg) }.not_to raise_error
        end
      end
    end

    context "with text messages" do
      it "does NOT emit audio_received event for text messages" do
        text_msg = { "id" => "wamid.text123", "timestamp" => "1749416383", "type" => "text", "text" => { "body" => "hello" } }

        allow_any_instance_of(Whatsapp::Processors::TextProcessor).to receive(:call)

        expect(Stream::Publisher).not_to receive(:new)

        described_class.perform_now(value, text_msg)
      end
    end
  end
end
