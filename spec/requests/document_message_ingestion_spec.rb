require 'rails_helper'

RSpec.describe "Document Message Ingestion", type: :request do
  describe "POST /ingest with document message" do
    let(:document_message_payload) do
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
                      "type" => "document",
                      "document" => {
                        "caption" => "my receipt",
                        "filename" => "receipt.pdf",
                        "mime_type" => "application/pdf",
                        "sha256" => "V5OPpLD/gEG6Xjg0MbmQDLFgcKsL+j5LfY4ny/pZ4MY=",
                        "id" => "622684793477189"
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
        post "/ingest",
             params: document_message_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:ok)
        expect(WebhookEvent.count).to eq(1)

        webhook_event = WebhookEvent.last
        expect(webhook_event.provider).to eq("whatsapp")
        expect(webhook_event.object_name).to eq("whatsapp_business_account")
      end

      it "enqueues IngestWebhookJob with webhook_event_id" do
        expect {
          post "/ingest",
               params: document_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        }.to have_enqueued_job(Whatsapp::IngestWebhookJob)
      end
    end

    context "job processing" do
      it "enqueues ProcessMessageJob for the document message" do
        perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob) do
          post "/ingest",
               params: document_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(Whatsapp::ProcessMessageJob).to have_been_enqueued
      end

      it "routes to DocumentProcessor" do
        # Mock media download to prevent actual API calls
        allow(Media::Downloader).to receive(:call).and_return("/tmp/receipt.pdf")

        expect_any_instance_of(Whatsapp::Processors::DocumentProcessor)
          .to receive(:call).and_call_original

        perform_enqueued_jobs do
          post "/ingest",
               params: document_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end
    end

    context "database record creation" do
      before do
        # Mock media download to prevent actual API calls
        allow(Media::Downloader).to receive(:call).and_return("/tmp/receipt.pdf")

        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: document_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end

      it "creates WaBusinessNumber record" do
        expect(WaBusinessNumber.count).to eq(1)

        business_number = WaBusinessNumber.last
        expect(business_number.display_phone_number).to eq("15550783881")
        expect(business_number.phone_number_id).to eq("106540352242922")
      end

      it "creates WaContact record" do
        expect(WaContact.count).to eq(1)

        contact = WaContact.last
        expect(contact.wa_id).to eq("16505551234")
        expect(contact.profile_name).to eq("Sheena Nelson")
      end

      it "creates WaMessage record with document attributes" do
        expect(WaMessage.count).to eq(1)

        message = WaMessage.last
        expect(message.type_name).to eq("document")
        expect(message.body_text).to eq("my receipt")
        expect(message.has_media).to eq(true)
        expect(message.media_kind).to eq("document")
        expect(message.provider_message_id).to eq("wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=")
        expect(message.direction).to eq("inbound")
        expect(message.status).to eq("received")
      end

      it "creates WaMedia record with document metadata" do
        expect(WaMedia.count).to eq(1)

        media = WaMedia.last
        expect(media.provider_media_id).to eq("622684793477189")
        expect(media.sha256).to eq("V5OPpLD/gEG6Xjg0MbmQDLFgcKsL+j5LfY4ny/pZ4MY=")
        expect(media.mime_type).to eq("application/pdf")
        expect(media.is_voice).to eq(false)
      end

      it "stores filename in message raw field" do
        message = WaMessage.last
        expect(message.raw).to be_present
        expect(message.raw["document_filename"]).to eq("receipt.pdf")
      end

      it "creates WaMessageMedia join record" do
        expect(WaMessageMedia.count).to eq(1)

        message_media = WaMessageMedia.last
        expect(message_media.wa_message_id).to eq(WaMessage.last.id)
        expect(message_media.wa_media_id).to eq(WaMedia.last.id)
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

      it "calls Media::Downloader to download the document" do
        expect(Media::Downloader).to have_received(:call).with(WaMedia.last.id)
      end
    end

    context "document without caption" do
      let(:document_no_caption_payload) do
        payload = document_message_payload.deep_dup
        payload["entry"][0]["changes"][0]["value"]["messages"][0]["document"].delete("caption")
        payload
      end

      it "creates message with nil body_text when caption is missing" do
        allow(Media::Downloader).to receive(:call).and_return("/tmp/receipt.pdf")

        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: document_no_caption_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        message = WaMessage.last
        expect(message.body_text).to be_nil
      end
    end

    context "idempotency" do
      it "handles duplicate webhook deliveries" do
        allow(Media::Downloader).to receive(:call).and_return("/tmp/receipt.pdf")

        # First delivery
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: document_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaMessage.count).to eq(1)
        expect(WaMedia.count).to eq(1)
        first_message_id = WaMessage.last.id
        first_media_id = WaMedia.last.id

        # Second delivery (duplicate)
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: document_message_payload.to_json,
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
