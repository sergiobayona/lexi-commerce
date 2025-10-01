require 'rails_helper'

RSpec.describe "Audio Message Ingestion", type: :request do
  # Stub Whisper module and classes for testing
  before(:all) do
    unless defined?(Whisper)
      module Whisper
        class Context
        end
        class Params
        end
      end
    end
  end
  describe "POST /ingest with audio message" do
    let(:audio_message_payload) do
      {
        "object" => "whatsapp_business_account",
        "entry" => [
          {
            "id" => "102290129340398",
            "changes" => [
              {
                "value" => {
                  "messaging_product" => "whatsapp",
                  "metadata" => {
                    "display_phone_number" => "15550783881",
                    "phone_number_id" => "106540352242922"
                  },
                  "contacts" => [
                    {
                      "profile" => {
                        "name" => "Sheena Nelson"
                      },
                      "wa_id" => "16505551234"
                    }
                  ],
                  "messages" => [
                    {
                      "from" => "16505551234",
                      "id" => "wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=",
                      "timestamp" => "1744344496",
                      "type" => "audio",
                      "audio" => {
                        "mime_type" => "audio/ogg; codecs=opus",
                        "sha256" => "wvqXMe6n7n1W0zphvLPoLj+s/NtKqmr3zZ7YzTP7xFI=",
                        "id" => "1908647269898587",
                        "voice" => true
                      }
                    }
                  ]
                },
                "field" => "messages"
              }
            ]
          }
        ]
      }
    end

    context "webhook reception" do
      it "returns 200 OK and creates WebhookEvent" do
        expect {
          post "/ingest",
               params: audio_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        }.to change { WebhookEvent.count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to be_empty

        webhook_event = WebhookEvent.last
        expect(webhook_event.provider).to eq("whatsapp")
        expect(webhook_event.object_name).to eq("whatsapp_business_account")
        expect(webhook_event.payload).to eq(audio_message_payload)
      end

      it "enqueues IngestWebhookJob with webhook_event_id" do
        expect {
          post "/ingest",
               params: audio_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        }.to have_enqueued_job(Whatsapp::IngestWebhookJob)

        expect(Whatsapp::IngestWebhookJob).to have_been_enqueued
      end
    end

    context "job processing" do
      it "enqueues ProcessMessageJob for the audio message" do
        post "/ingest",
             params: audio_message_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob)

        expect(Whatsapp::ProcessMessageJob).to have_been_enqueued
      end

      it "routes to AudioProcessor" do
        # Mock the download and transcription to focus on routing
        allow(Media::Downloader).to receive(:call).and_return("/tmp/test.ogg")
        allow(Media::AudioConverter).to receive(:to_wav).and_return("/tmp/test.wav")

        # Mock Whisper transcription
        whisper_context = double("Whisper::Context")
        allow(Whisper::Context).to receive(:new).and_return(whisper_context)
        allow(whisper_context).to receive(:transcribe).and_yield("test transcription")

        expect_any_instance_of(Whatsapp::Processors::AudioProcessor)
          .to receive(:call).and_call_original

        perform_enqueued_jobs do
          post "/ingest",
               params: audio_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end
    end

    context "database record creation" do
      before do
        # Mock download and transcription to focus on database records
        allow(Media::Downloader).to receive(:call).and_return("/tmp/test.ogg")
        allow(Media::AudioConverter).to receive(:to_wav).and_return("/tmp/test.wav")

        # Mock Whisper transcription
        whisper_context = double("Whisper::Context")
        allow(Whisper::Context).to receive(:new).and_return(whisper_context)
        allow(whisper_context).to receive(:transcribe).and_yield("test transcription")

        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: audio_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end

      it "creates WaBusinessNumber record" do
        expect(WaBusinessNumber.count).to eq(1)

        business_number = WaBusinessNumber.last
        expect(business_number.phone_number_id).to eq("106540352242922")
        expect(business_number.display_phone_number).to eq("15550783881")
      end

      it "creates WaContact record" do
        expect(WaContact.count).to eq(1)

        contact = WaContact.last
        expect(contact.wa_id).to eq("16505551234")
        expect(contact.profile_name).to eq("Sheena Nelson")
      end

      it "creates WaMessage record with audio attributes" do
        expect(WaMessage.count).to eq(1)

        message = WaMessage.last
        expect(message.provider_message_id).to eq("wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=")
        expect(message.direction).to eq("inbound")
        expect(message.type_name).to eq("audio")
        expect(message.has_media).to eq(true)
        expect(message.media_kind).to eq("audio")
        expect(message.timestamp).to eq(Time.at(1744344496).utc)
        expect(message.status).to eq("received")
      end

      it "creates WaMedia record with audio metadata" do
        expect(WaMedia.count).to eq(1)

        media = WaMedia.last
        expect(media.provider_media_id).to eq("1908647269898587")
        expect(media.sha256).to eq("wvqXMe6n7n1W0zphvLPoLj+s/NtKqmr3zZ7YzTP7xFI=")
        expect(media.mime_type).to eq("audio/ogg; codecs=opus")
        expect(media.is_voice).to eq(true)
        # Note: download_status may vary based on mock success/failure
      end

      it "creates WaMessageMedia join record" do
        expect(WaMessageMedia.count).to eq(1)

        message_media = WaMessageMedia.last
        expect(message_media.wa_message).to eq(WaMessage.last)
        expect(message_media.wa_media).to eq(WaMedia.last)
        expect(message_media.purpose).to eq("primary")
      end

      it "establishes correct relationships" do
        message = WaMessage.last
        contact = WaContact.last
        business_number = WaBusinessNumber.last
        media = WaMedia.last

        expect(message.wa_contact).to eq(contact)
        expect(message.wa_business_number).to eq(business_number)
        expect(message.wa_media).to eq(media)
      end
    end

    context "audio event emission" do
      before do
        # Mock intent handler to not send welcome message
        allow_any_instance_of(Whatsapp::Intent::Handler).to receive(:call).and_return({
          intent_result: { label: :other, confidence: 0.5 },
          actions: { welcome_message_sent: false }
        })
      end
    end

    context "idempotency" do
      it "handles duplicate webhook deliveries" do
        # Mock download and transcription
        allow(Media::Downloader).to receive(:call).and_return("/tmp/test.ogg")
        allow(Media::AudioConverter).to receive(:to_wav).and_return("/tmp/test.wav")

        whisper_context = double("Whisper::Context")
        allow(Whisper::Context).to receive(:new).and_return(whisper_context)
        allow(whisper_context).to receive(:transcribe).and_yield("test transcription")

        # First delivery
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: audio_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaMessage.count).to eq(1)
        expect(WaMedia.count).to eq(1)
        first_message_id = WaMessage.last.id
        first_media_id = WaMedia.last.id

        # Second delivery (duplicate)
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: audio_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        # Should still have only one message and media (upsert on unique keys)
        expect(WaMessage.count).to eq(1)
        expect(WaMedia.count).to eq(1)
        expect(WaMessage.last.id).to eq(first_message_id)
        expect(WaMedia.last.id).to eq(first_media_id)
      end
    end
  end
end
