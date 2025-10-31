require 'rails_helper'

RSpec.describe "Contact Message Ingestion", type: :request do
  describe "POST /ingest with contact message" do
    let(:contact_message_payload) do
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
                      "type" => "contacts",
                      "contacts" => [
                        {
                          "name" => {
                            "first_name" => "Barbara",
                            "last_name" => "Johnson",
                            "formatted_name" => "Barbara J. Johnson"
                          },
                          "org" => {
                            "company" => "Social Tsunami"
                          },
                          "phones" => [
                            {
                              "phone" => "+1 (415) 555-0829",
                              "wa_id" => "14125550829",
                              "type" => "MOBILE"
                            }
                          ]
                        }
                      ]
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
             params: contact_message_payload.to_json,
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
               params: contact_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        }.to have_enqueued_job(Whatsapp::IngestWebhookJob)
      end
    end

    context "job processing" do
      it "enqueues ProcessMessageJob for the contact message" do
        perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob) do
          post "/ingest",
               params: contact_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(Whatsapp::ProcessMessageJob).to have_been_enqueued
      end

      it "routes to ContactProcessor" do
        expect_any_instance_of(Whatsapp::Processors::ContactProcessor)
          .to receive(:call).and_call_original

        perform_enqueued_jobs do
          post "/ingest",
               params: contact_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end
    end

    context "database record creation" do
      before do
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: contact_message_payload.to_json,
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

      it "creates WaMessage record with contacts type" do
        expect(WaMessage.count).to eq(1)

        message = WaMessage.last
        expect(message.type_name).to eq("contacts")
        expect(message.body_text).to eq("Barbara J. Johnson")
        expect(message.has_media).to eq(false)
        expect(message.provider_message_id).to eq("wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=")
        expect(message.direction).to eq("inbound")
        expect(message.status).to eq("received")
      end

      it "stores shared contacts data in raw field" do
        message = WaMessage.last
        raw_data = message.raw

        expect(raw_data["shared_contacts"]).to be_present
        expect(raw_data["shared_contacts"].length).to eq(1)

        shared_contact = raw_data["shared_contacts"].first
        expect(shared_contact["name"]["formatted_name"]).to eq("Barbara J. Johnson")
        expect(shared_contact["name"]["first_name"]).to eq("Barbara")
        expect(shared_contact["name"]["last_name"]).to eq("Johnson")
        expect(shared_contact["org"]["company"]).to eq("Social Tsunami")
        expect(shared_contact["phones"].first["phone"]).to eq("+1 (415) 555-0829")
        expect(shared_contact["phones"].first["wa_id"]).to eq("14125550829")
        expect(shared_contact["phones"].first["type"]).to eq("MOBILE")
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

    context "multiple contacts in one message" do
      let(:multiple_contacts_payload) do
        payload = contact_message_payload.deep_dup
        payload["entry"][0]["changes"][0]["value"]["messages"][0]["contacts"] << {
          "name" => {
            "first_name" => "John",
            "last_name" => "Doe",
            "formatted_name" => "John Doe"
          },
          "phones" => [
            {
              "phone" => "+1 (555) 123-4567",
              "type" => "WORK"
            }
          ]
        }
        payload
      end

      it "stores all contacts and creates searchable body_text" do
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: multiple_contacts_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        message = WaMessage.last
        expect(message.body_text).to eq("Barbara J. Johnson, John Doe")
        expect(message.raw["shared_contacts"].length).to eq(2)
      end
    end

    context "idempotency" do
      it "handles duplicate webhook deliveries" do
        # First delivery
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: contact_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaMessage.count).to eq(1)
        first_message_id = WaMessage.last.id

        # Second delivery (duplicate)
        perform_enqueued_jobs(only: [ Whatsapp::IngestWebhookJob, Whatsapp::ProcessMessageJob ]) do
          post "/ingest",
               params: contact_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        # Should still have only one message (upsert on unique key)
        expect(WaMessage.count).to eq(1)
        expect(WaMessage.last.id).to eq(first_message_id)
      end
    end
  end
end
