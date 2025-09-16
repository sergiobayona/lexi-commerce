require 'rails_helper'

RSpec.describe "Ingestion Webhook", type: :request do
  describe "POST /ingest" do
    context "with valid WhatsApp text message payload" do
      let(:whatsapp_text_payload) do
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
                        "timestamp" => "1749416383",
                        "type" => "text",
                        "text" => {
                          "body" => "Does it come in another color?"
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

      it "successfully processes WhatsApp text message and enqueues jobs" do
        # Ensure we start with clean state
        expect(WebhookEvent.count).to eq(0)

        # Test job enqueueing
        expect {
          post "/ingest",
               params: whatsapp_text_payload.to_json,
               headers: {
                 "Content-Type" => "application/json"
                 # Note: No X-Hub-Signature-256 header - allowed in dev mode
               }
        }.to have_enqueued_job(Whatsapp::IngestWebhookJob)
         .with(whatsapp_text_payload)

        # Should return 200 OK
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_empty

        # Should create a WebhookEvent record
        expect(WebhookEvent.count).to eq(1)

        webhook_event = WebhookEvent.last
        expect(webhook_event.provider).to eq("whatsapp")
        expect(webhook_event.object_name).to eq("whatsapp_business_account")
        expect(webhook_event.payload).to eq(whatsapp_text_payload)

        # Verify the job was enqueued with correct arguments
        expect(Whatsapp::IngestWebhookJob).to have_been_enqueued.with(whatsapp_text_payload)
      end
    end
  end
end
