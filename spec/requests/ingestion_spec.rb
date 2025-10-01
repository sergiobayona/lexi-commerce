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

        # Should return 200 OK
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_empty

        # Should create a WebhookEvent record
        expect(WebhookEvent.count).to eq(1)

        webhook_event = WebhookEvent.last
        expect(webhook_event.provider).to eq("whatsapp")
        expect(webhook_event.object_name).to eq("whatsapp_business_account")
        expect(webhook_event.payload).to eq(whatsapp_text_payload)

        # Verify the job was enqueued (with payload and webhook_event_id)
        expect(Whatsapp::IngestWebhookJob).to have_been_enqueued
      end

      it "executes full processing pipeline creating proper records and calling TextProcessor" do
        # Ensure clean state
        expect(WebhookEvent.count).to eq(0)
        expect(WaBusinessNumber.count).to eq(0)
        expect(WaContact.count).to eq(0)
        expect(WaMessage.count).to eq(0)

        # Perform the request
        post "/ingest",
             params: whatsapp_text_payload.to_json,
             headers: { "Content-Type" => "application/json" }

        # Verify HTTP response
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_empty

        # Verify WebhookEvent was created
        expect(WebhookEvent.count).to eq(1)
        webhook_event = WebhookEvent.last
        expect(webhook_event.provider).to eq("whatsapp")
        expect(webhook_event.object_name).to eq("whatsapp_business_account")

        # Execute the enqueued IngestWebhookJob
        perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob)

        # Verify ProcessMessageJob was enqueued
        expect(Whatsapp::ProcessMessageJob).to have_been_enqueued

        # Execute the ProcessMessageJob to trigger TextProcessor
        value = whatsapp_text_payload["entry"][0]["changes"][0]["value"]
        message_data = value["messages"][0]

        # Verify TextProcessor is called
        expect_any_instance_of(Whatsapp::Processors::TextProcessor)
          .to receive(:call).and_call_original

        perform_enqueued_jobs(only: Whatsapp::ProcessMessageJob)

        # Verify database records were created

        # 1. Business Number
        expect(WaBusinessNumber.count).to eq(1)
        business_number = WaBusinessNumber.last
        expect(business_number.phone_number_id).to eq("106540352242922")
        expect(business_number.display_phone_number).to eq("15550783881")

        # 2. Contact
        expect(WaContact.count).to eq(1)
        contact = WaContact.last
        expect(contact.wa_id).to eq("16505551234")
        expect(contact.profile_name).to eq("Sheena Nelson")

        # 3. Message
        expect(WaMessage.count).to eq(1)
        message = WaMessage.last
        expect(message.provider_message_id).to eq("wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=")
        expect(message.direction).to eq("inbound")
        expect(message.type_name).to eq("text")
        expect(message.body_text).to eq("Does it come in another color?")
        expect(message.has_media).to eq(false)
        expect(message.media_kind).to be_nil
        expect(message.wa_contact_id).to eq(contact.id)
        expect(message.wa_business_number_id).to eq(business_number.id)
        expect(message.timestamp).to eq(Time.at(1749416383).utc)

        # Verify relationships
        expect(message.wa_contact).to eq(contact)
        expect(message.wa_business_number).to eq(business_number)
      end
    end
  end
end
