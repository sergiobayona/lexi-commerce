# WhatsApp Text Message Ingestion - Complete Test Flow

## Overview
This document describes the complete flow tested by the integration spec in `spec/requests/ingestion_spec.rb` for processing WhatsApp text message webhooks.

## Test Payload
```json
{
  "object": "whatsapp_business_account",
  "entry": [
    {
      "id": "102290129340398",
      "changes": [
        {
          "value": {
            "messaging_product": "whatsapp",
            "metadata": {
              "display_phone_number": "15550783881",
              "phone_number_id": "106540352242922"
            },
            "contacts": [
              {
                "profile": {
                  "name": "Sheena Nelson"
                },
                "wa_id": "16505551234"
              }
            ],
            "messages": [
              {
                "from": "16505551234",
                "id": "wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=",
                "timestamp": "1749416383",
                "type": "text",
                "text": {
                  "body": "Does it come in another color?"
                }
              }
            ]
          },
          "field": "messages"
        }
      ]
    }
  ]
}
```

## Complete Processing Flow

### 1. HTTP Request → Controller
**Route**: `POST /ingest` → `WebhooksController#create`

**Controller Actions** (`app/controllers/webhooks_controller.rb`):
- Parses JSON payload
- Creates `WebhookEvent` record with:
  - `provider`: "whatsapp"
  - `object_name`: "whatsapp_business_account"
  - `payload`: Full JSON payload (JSONB)
- Enqueues `Whatsapp::IngestWebhookJob`
- Returns HTTP 200 OK

**Test Verification**:
```ruby
expect(response).to have_http_status(:ok)
expect(WebhookEvent.count).to eq(1)
expect(Whatsapp::IngestWebhookJob).to have_been_enqueued
```

---

### 2. IngestWebhookJob Processing
**Job**: `Whatsapp::IngestWebhookJob` (`app/jobs/whatsapp/ingest_webhook_job.rb`)

**Actions**:
- Iterates through `payload["entry"]`
- Extracts `value` from each change
- Validates `messaging_product == "whatsapp"`
- For each message in `value["messages"]`:
  - Enqueues `Whatsapp::ProcessMessageJob` with `(value, msg)`

**Test Verification**:
```ruby
perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob)
expect(Whatsapp::ProcessMessageJob).to have_been_enqueued
```

---

### 3. ProcessMessageJob Routing
**Job**: `Whatsapp::ProcessMessageJob` (`app/jobs/whatsapp/process_message_job.rb`)

**Message Type Routing**:
```ruby
type = msg["type"]  # "text" in this case
case type
when "text"
  Whatsapp::Processors::TextProcessor.new(value, msg).call
when "audio"
  Whatsapp::Processors::AudioProcessor.new(value, msg).call
else
  Whatsapp::Processors::BaseProcessor.new(value, msg).call
end
```

**For Text Messages**: Routes to `TextProcessor`

**Test Verification**:
```ruby
expect_any_instance_of(Whatsapp::Processors::TextProcessor)
  .to receive(:call).and_call_original

perform_enqueued_jobs(only: Whatsapp::ProcessMessageJob)
```

---

### 4. TextProcessor Creates Database Records
**Processor**: `Whatsapp::Processors::TextProcessor` (`app/services/whatsapp/processors/text_processor.rb`)

**Database Operations** (in order):

#### 4.1 Upsert Business Number
```ruby
number = upsert_business_number!(@value["metadata"])
```

Creates/updates `WaBusinessNumber`:
- `phone_number_id`: "106540352242922"
- `display_phone_number`: "15550783881"

#### 4.2 Upsert Contact
```ruby
contact = upsert_contact!(@value["contacts"]&.first)
```

Creates/updates `WaContact`:
- `wa_id`: "16505551234"
- `profile_name`: "Sheena Nelson"

#### 4.3 Create Message Record
```ruby
attrs = common_message_attrs(number, contact).merge(
  type_name: "text",
  has_media: false,
  media_kind: nil
)
msg = upsert_message!(attrs)
msg.update!(body_text: @msg.dig("text", "body"))
```

Creates `WaMessage`:
- `provider_message_id`: "wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA="
- `direction`: "inbound"
- `type_name`: "text"
- `body_text`: "Does it come in another color?"
- `has_media`: false
- `media_kind`: nil
- `wa_contact_id`: (contact ID)
- `wa_business_number_id`: (business number ID)
- `timestamp`: 2025-06-08 20:59:43 UTC
- `status`: "received"

**Test Verification**:
```ruby
# Business Number
expect(WaBusinessNumber.count).to eq(1)
business_number = WaBusinessNumber.last
expect(business_number.phone_number_id).to eq("106540352242922")

# Contact
expect(WaContact.count).to eq(1)
contact = WaContact.last
expect(contact.wa_id).to eq("16505551234")

# Message
expect(WaMessage.count).to eq(1)
message = WaMessage.last
expect(message.type_name).to eq("text")
expect(message.body_text).to eq("Does it come in another color?")

# Relationships
expect(message.wa_contact).to eq(contact)
expect(message.wa_business_number).to eq(business_number)
```

---

## Database Schema Summary

### Tables Created/Updated:
1. **webhook_events** - Raw webhook payload storage
2. **wa_business_numbers** - WhatsApp business phone numbers
3. **wa_contacts** - WhatsApp user contacts
4. **wa_messages** - Message records with relationships

### Key Relationships:
- `WaMessage` belongs_to `WaContact`
- `WaMessage` belongs_to `WaBusinessNumber`
- Unique constraint on `provider_message_id` ensures idempotency

---

## Test Execution

### Run Full Integration Test:
```bash
bundle exec rspec spec/requests/ingestion_spec.rb:79 --format documentation
```

### Expected Output:
```
Ingestion Webhook
  POST /ingest
    with valid WhatsApp text message payload
      executes full processing pipeline creating proper records and calling TextProcessor

Finished in 0.17211 seconds
1 example, 0 failures
```

---

## Key Testing Patterns

### 1. Job Execution
Uses `perform_enqueued_jobs` to synchronously execute background jobs in tests:
```ruby
perform_enqueued_jobs(only: Whatsapp::IngestWebhookJob)
perform_enqueued_jobs(only: Whatsapp::ProcessMessageJob)
```

### 2. Processor Verification
Verifies correct processor is called:
```ruby
expect_any_instance_of(Whatsapp::Processors::TextProcessor)
  .to receive(:call).and_call_original
```

### 3. Database State Validation
Checks all database records and relationships:
- Record counts
- Attribute values
- Foreign key relationships
- Timestamps

---

## Flow Diagram

```
POST /ingest
    ↓
WebhooksController#create
    ↓
1. Create WebhookEvent record
2. Enqueue IngestWebhookJob
3. Return 200 OK
    ↓
IngestWebhookJob.perform
    ↓
Extract messages → Enqueue ProcessMessageJob(value, msg)
    ↓
ProcessMessageJob.perform
    ↓
Route by msg["type"]
    ↓
TextProcessor.call (for "text" messages)
    ↓
1. Upsert WaBusinessNumber
2. Upsert WaContact
3. Create WaMessage
4. Update body_text
    ↓
Database Records Created ✓
```

---

## Notes

- **Idempotency**: `provider_message_id` ensures duplicate webhooks don't create duplicate messages
- **Upsert Strategy**: Business numbers and contacts are upserted (created or updated)
- **Message Uniqueness**: Messages use unique constraint on `provider_message_id`
- **Timestamp Handling**: Unix timestamps converted to UTC datetime
- **Type Safety**: Message type determines processor routing
