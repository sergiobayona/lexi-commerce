require 'rails_helper'

RSpec.describe "Button Message Ingestion", type: :request do
  describe "POST /ingest with button message" do
    let(:button_message_payload) do
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
                      "context" => {
                        "from" => "15550783881",
                        "id" => "wamid.HBgLMTQxMjU1NTA4MjkVAgASGBQzQUNCNjk5RDUwNUZGMUZEM0VBRAA="
                      },
                      "from" => "16505551234",
                      "id" => "wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQUFERjg0NDEzNDdFODU3MUMxMAA=",
                      "timestamp" => "1750091045",
                      "type" => "button",
                      "button" => {
                        "payload" => "Unsubscribe",
                        "text" => "Unsubscribe"
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
             params: button_message_payload.to_json,
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
               params: button_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        }.to have_enqueued_job(Whatsapp::IngestWebhookJob)
      end
    end

    context "job processing" do
      it "enqueues ProcessMessageJob for the button message" do
        perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob) do
          post "/ingest",
               params: button_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(Whatsapp::ProcessMessageJob).to have_been_enqueued
      end

      it "routes to ButtonProcessor" do
        expect_any_instance_of(Whatsapp::Processors::ButtonProcessor)
          .to receive(:call).and_call_original

        perform_enqueued_jobs do
          post "/ingest",
               params: button_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end
    end

    context "database record creation" do
      before do
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: button_message_payload.to_json,
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

      it "creates WaMessage record with button attributes" do
        expect(WaMessage.count).to eq(1)

        message = WaMessage.last
        expect(message.type_name).to eq("button")
        expect(message.body_text).to eq("Unsubscribe")
        expect(message.has_media).to eq(false)
        expect(message.provider_message_id).to eq("wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQUFERjg0NDEzNDdFODU3MUMxMAA=")
        expect(message.direction).to eq("inbound")
        expect(message.status).to eq("received")
      end

      it "stores button payload and context in raw field" do
        message = WaMessage.last
        raw_data = message.raw

        expect(raw_data["button_payload"]).to eq("Unsubscribe")
        expect(raw_data["button_text"]).to eq("Unsubscribe")
        expect(raw_data["context_message_id"]).to eq("wamid.HBgLMTQxMjU1NTA4MjkVAgASGBQzQUNCNjk5RDUwNUZGMUZEM0VBRAA=")
        expect(raw_data["context_from"]).to eq("15550783881")
      end

      it "does not create media records" do
        expect(WaMedia.count).to eq(0)
        expect(WaMessageMedia.count).to eq(0)
      end

      it "establishes correct relationships" do
        message = WaMessage.last
        contact = WaContact.last
        business_number = WaBusinessNumber.last

        expect(message.wa_contact).to eq(contact)
        expect(message.wa_business_number).to eq(business_number)
      end
    end

    context "idempotency" do
      it "handles duplicate webhook deliveries" do
        # First delivery
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: button_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaMessage.count).to eq(1)
        first_message_id = WaMessage.last.id

        # Second delivery (duplicate)
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: button_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        # Should still have only one message (upsert on unique key)
        expect(WaMessage.count).to eq(1)
        expect(WaMessage.last.id).to eq(first_message_id)
      end
    end
  end
end
