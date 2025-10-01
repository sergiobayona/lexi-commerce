require 'rails_helper'

RSpec.describe "WhatsApp Error Handling", type: :request do
  describe "POST /ingest with errors" do
    context "with system-level errors" do
      let(:system_error_payload) do
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
                    "errors" => [
                      {
                        "code" => 131047,
                        "title" => "Service unavailable",
                        "message" => "Service temporarily unavailable. Please retry your request",
                        "error_data" => {
                          "details" => "Too Many Requests"
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

      it "creates WaError record for system errors" do
        perform_enqueued_jobs do
          post "/ingest",
               params: system_error_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaError.count).to eq(1)

        expect(response).to have_http_status(:ok)

        error = WaError.last
        expect(error.error_type).to eq("system")
        expect(error.error_level).to eq("error")
        expect(error.error_code).to eq(131047)
        expect(error.error_title).to eq("Service unavailable")
        expect(error.error_message).to eq("Service temporarily unavailable. Please retry your request")
        expect(error.provider_message_id).to be_nil
        expect(error.wa_message_id).to be_nil
        expect(error.resolved).to eq(false)
      end

      it "logs system errors appropriately" do
        expect(Rails.logger).to receive(:error).with(
          a_string_including('"at":"whatsapp.error.system"')
            .and(a_string_including('"error_code":131047'))
            .and(a_string_including('"error_level":"error"'))
        )

        perform_enqueued_jobs do
          post "/ingest",
               params: system_error_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end
    end

    context "with unsupported message errors" do
      let(:unsupported_message_payload) do
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
                          "name" => "John Doe"
                        },
                        "wa_id" => "16505551234"
                      }
                    ],
                    "messages" => [
                      {
                        "from" => "16505551234",
                        "id" => "wamid.unsupported123",
                        "timestamp" => "1749416383",
                        "type" => "unsupported",
                        "errors" => [
                          {
                            "code" => 131051,
                            "title" => "Unsupported message type",
                            "message" => "Message type is not currently supported"
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

      it "creates WaError record for unsupported messages" do
        perform_enqueued_jobs do
          post "/ingest",
               params: unsupported_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaError.count).to eq(1)

        expect(response).to have_http_status(:ok)

        error = WaError.last
        expect(error.error_type).to eq("message")
        expect(error.error_code).to eq(131051)
        expect(error.error_title).to eq("Unsupported message type")
        expect(error.provider_message_id).to eq("wamid.unsupported123")
      end

      it "does not process unsupported messages normally" do
        # Verify that normal message processing is skipped
        expect_any_instance_of(Whatsapp::Processors::TextProcessor).not_to receive(:call)
        expect_any_instance_of(Whatsapp::Processors::AudioProcessor).not_to receive(:call)

        perform_enqueued_jobs do
          post "/ingest",
               params: unsupported_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end

      it "logs unsupported message warning" do
        expect(Rails.logger).to receive(:warn).with(
          a_string_including('"at":"process_message.unsupported"')
            .and(a_string_including('"provider_message_id":"wamid.unsupported123"'))
        )

        perform_enqueued_jobs do
          post "/ingest",
               params: unsupported_message_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end
      end
    end

    context "with status errors" do
      let!(:wa_message) { create(:wa_message, provider_message_id: "wamid.failed123") }

      let(:status_error_payload) do
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
                    "statuses" => [
                      {
                        "id" => "wamid.failed123",
                        "status" => "failed",
                        "timestamp" => "1749416400",
                        "errors" => [
                          {
                            "code" => 131026,
                            "title" => "Message undeliverable",
                            "message" => "Message failed to send"
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

      it "creates WaError record for status errors" do
        perform_enqueued_jobs do
          post "/ingest",
               params: status_error_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaError.count).to eq(1)

        expect(response).to have_http_status(:ok)

        error = WaError.last
        expect(error.error_type).to eq("status")
        expect(error.error_code).to eq(131026)
        expect(error.error_title).to eq("Message undeliverable")
        expect(error.provider_message_id).to eq("wamid.failed123")
        expect(error.wa_message_id).to eq(wa_message.id)
      end

      it "does not create status event for failed status" do
        perform_enqueued_jobs do
          post "/ingest",
               params: status_error_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaMessageStatusEvent.count).to eq(0)
      end
    end

    context "with successful status updates (no errors)" do
      let!(:wa_message) { create(:wa_message, provider_message_id: "wamid.success123", status: "sent") }

      let(:status_success_payload) do
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
                    "statuses" => [
                      {
                        "id" => "wamid.success123",
                        "status" => "delivered",
                        "timestamp" => "1749416400"
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

      it "creates status event and updates message status" do
        perform_enqueued_jobs do
          post "/ingest",
               params: status_success_payload.to_json,
               headers: { "Content-Type" => "application/json" }
        end

        expect(WaMessageStatusEvent.count).to eq(1)

        expect(response).to have_http_status(:ok)

        # Check status event
        status_event = WaMessageStatusEvent.last
        expect(status_event.provider_message_id).to eq("wamid.success123")
        expect(status_event.event_type).to eq("delivered")

        # Check message status updated
        wa_message.reload
        expect(wa_message.status).to eq("delivered")
      end
    end
  end
end
