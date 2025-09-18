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

      context "when intent handler does NOT send welcome message" do
        it "emits audio_received event to Redis stream" do
          # Mock intent handler to return no welcome message sent
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }
          allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return(handler_result)

          # Mock the stream publisher
          stream_publisher = instance_double(Stream::Publisher)
          allow(Stream::Publisher).to receive(:new).and_return(stream_publisher)

          # Create the message and media records that would be created by AudioProcessor
          wa_message = WaMessage.create!(
            provider_message_id: "wamid.audio123",
            direction: "inbound",
            wa_contact: contact,
            wa_business_number: business_number,
            type_name: "audio",
            timestamp: Time.at(1749416383).utc,
            status: "received"
          )

          wa_media = WaMedia.create!(
            provider_media_id: "media.audio",
            sha256: "abc123",
            mime_type: "audio/ogg"
          )

          WaMessageMedia.create!(
            wa_message: wa_message,
            wa_media: wa_media,
            purpose: "primary"
          )

          # Expected payload
          expected_payload = {
            provider: "whatsapp",
            provider_message_id: "wamid.audio123",
            wa_message_id: wa_message.id,
            wa_contact_id: contact.id,
            user_e164: "16505551234",
            media: {
              provider_media_id: "media.audio",
              sha256: "abc123",
              mime_type: "audio/ogg",
              bytes: nil
            },
            business_number_id: business_number.id,
            timestamp: wa_message.timestamp.iso8601
          }

          expect(stream_publisher).to receive(:publish)
            .with(expected_payload, idempotency_key: "audio_received:wamid.audio123")

          described_class.perform_now(value, audio_msg)
        end

        it "calls emit_audio_received_event when conditions are met" do
          # Setup similar to above test
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }
          allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return(handler_result)

          stream_publisher = instance_double(Stream::Publisher)
          allow(Stream::Publisher).to receive(:new).and_return(stream_publisher)
          allow(stream_publisher).to receive(:publish)

          wa_message = WaMessage.create!(
            provider_message_id: "wamid.audio123",
            direction: "inbound",
            wa_contact: contact,
            wa_business_number: business_number,
            type_name: "audio",
            timestamp: Time.at(1749416383).utc,
            status: "received"
          )

          wa_media = WaMedia.create!(
            provider_media_id: "media.audio",
            sha256: "abc123",
            mime_type: "audio/ogg"
          )

          WaMessageMedia.create!(wa_message: wa_message, wa_media: wa_media, purpose: "primary")

          # Spy on the private method call
          job_instance = described_class.new
          expect(job_instance).to receive(:emit_audio_received_event).with("wamid.audio123", value)

          job_instance.perform(value, audio_msg)
        end
      end

      context "when intent handler DOES send welcome message" do
        it "does NOT emit audio_received event" do
          # Mock intent handler to return welcome message sent
          handler_result = {
            intent_result: { label: :onboard_greeting, confidence: 0.9 },
            actions: { welcome_message_sent: true }
          }
          allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return(handler_result)

          # Stream publisher should not be called
          expect(Stream::Publisher).not_to receive(:new)

          described_class.perform_now(value, audio_msg)
        end
      end

      context "when audio message/media records are missing" do
        it "handles missing wa_message gracefully" do
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }
          allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return(handler_result)

          # No message record created, so emit_audio_received_event should return early
          expect(Stream::Publisher).not_to receive(:new)

          expect { described_class.perform_now(value, audio_msg) }.not_to raise_error
        end

        it "handles missing wa_media gracefully" do
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }
          allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return(handler_result)

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

      context "when Stream::Publisher raises an error" do
        it "logs the error and continues processing" do
          handler_result = {
            intent_result: { label: :other, confidence: 0.5 },
            actions: { welcome_message_sent: false }
          }
          allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return(handler_result)

          # Setup records
          wa_message = WaMessage.create!(
            provider_message_id: "wamid.audio123",
            direction: "inbound",
            wa_contact: contact,
            wa_business_number: business_number,
            type_name: "audio",
            timestamp: Time.at(1749416383).utc,
            status: "received"
          )

          wa_media = WaMedia.create!(
            provider_media_id: "media.audio",
            sha256: "abc123",
            mime_type: "audio/ogg"
          )

          WaMessageMedia.create!(wa_message: wa_message, wa_media: wa_media, purpose: "primary")

          # Mock Stream::Publisher to raise error
          stream_publisher = instance_double(Stream::Publisher)
          allow(Stream::Publisher).to receive(:new).and_return(stream_publisher)
          allow(stream_publisher).to receive(:publish).and_raise(Stream::Publisher::PublishError, "Redis connection failed")

          expect(Rails.logger).to receive(:error).with(
            a_string_including('"at":"process_message.emit_audio_event_error"')
              .and(a_string_including('"provider_message_id":"wamid.audio123"'))
              .and(a_string_including('"error":"Stream::Publisher::PublishError"'))
              .and(a_string_including('"message":"Redis connection failed"'))
          )

          expect { described_class.perform_now(value, audio_msg) }.not_to raise_error
        end
      end
    end

    context "with text messages" do
      it "does NOT emit audio_received event for text messages" do
        text_msg = { "id" => "wamid.text123", "timestamp" => "1749416383", "type" => "text", "text" => { "body" => "hello" } }

        allow_any_instance_of(Whatsapp::Processors::TextProcessor).to receive(:call)
        allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return({
          intent_result: { label: :other, confidence: 0.5 },
          actions: { welcome_message_sent: false }
        })

        expect(Stream::Publisher).not_to receive(:new)

        described_class.perform_now(value, text_msg)
      end
    end
  end
end
