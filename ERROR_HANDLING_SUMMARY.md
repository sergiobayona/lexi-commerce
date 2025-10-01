# WhatsApp Error Handling Implementation Summary

## Overview
Comprehensive error handling system for WhatsApp webhook errors across three error surfaces: system-level, message-level, and status-level errors.

## Database Schema

### New Table: `wa_errors`

Tracks all errors from WhatsApp API webhooks:

```ruby
create_table :wa_errors do |t|
  # Error classification
  t.string :error_type, null: false      # 'system', 'message', 'status'
  t.string :error_level, null: false     # 'error', 'warning', 'info'

  # Error details
  t.integer :error_code
  t.string :error_title
  t.text :error_message
  t.text :error_details

  # Context
  t.string :provider_message_id          # For message and status errors
  t.bigint :wa_message_id                # Link to wa_message if exists
  t.bigint :webhook_event_id             # Link to webhook event

  # Raw error data
  t.jsonb :raw_error_data, default: {}, null: false

  # Metadata
  t.boolean :resolved, default: false
  t.text :resolution_notes
  t.datetime :resolved_at

  t.timestamps
end
```

**Indexes**: error_type, error_level, error_code, provider_message_id, wa_message_id, webhook_event_id, resolved, created_at, raw_error_data (GIN)

---

## Error Types

### 1. System/App/Account-Level Errors
**Location in payload**: `entry.changes.value.errors[]`

**Example**:
```json
{
  "errors": [
    {
      "code": 131047,
      "title": "Service unavailable",
      "message": "Service temporarily unavailable. Please retry your request",
      "error_data": {
        "details": "Too Many Requests"
      }
    }
  ]
}
```

**Handling**:
- Processed in `Whatsapp::IngestWebhookJob`
- Creates `WaError` with `error_type: 'system'`
- No `provider_message_id` or `wa_message_id`
- Logs at ERROR level

### 2. Incoming Message Errors (Unsupported)
**Location in payload**: `entry.changes.value.messages[].errors[]` or `type: "unsupported"`

**Example**:
```json
{
  "messages": [
    {
      "from": "16505551234",
      "id": "wamid.unsupported123",
      "timestamp": "1749416383",
      "type": "unsupported",
      "errors": [
        {
          "code": 131051,
          "title": "Unsupported message type",
          "message": "Message type is not currently supported"
        }
      ]
    }
  ]
}
```

**Handling**:
- Detected in `Whatsapp::ProcessMessageJob`
- Early return - does NOT process message normally
- Creates `WaError` with `error_type: 'message'`
- Includes `provider_message_id`
- Links to `wa_message_id` if message record exists
- Logs at WARN level

### 3. Outgoing Message Status Errors
**Location in payload**: `entry.changes.value.statuses[].errors[]`

**Example**:
```json
{
  "statuses": [
    {
      "id": "wamid.failed123",
      "status": "failed",
      "timestamp": "1749416400",
      "errors": [
        {
          "code": 131026,
          "title": "Message undeliverable",
          "message": "Message failed to send"
        }
      ]
    }
  ]
}
```

**Handling**:
- Processed in `Whatsapp::ProcessStatusJob`
- Early return - does NOT create status event
- Creates `WaError` with `error_type: 'status'`
- Includes `provider_message_id`
- Links to `wa_message_id` if found
- Logs at ERROR level

---

## Implementation Components

### 1. WaError Model
**Location**: `app/models/wa_error.rb`

**Features**:
- Enums for `error_type` and `error_level`
- Scopes: `unresolved`, `resolved`, `recent`, `by_type`, `by_level`, `critical`
- Instance methods: `resolve!`, `error_summary`
- Associations: `belongs_to :wa_message, optional: true`, `belongs_to :webhook_event, optional: true`

### 2. ErrorProcessor Service
**Location**: `app/services/whatsapp/processors/error_processor.rb`

**Responsibilities**:
- Process system/app/account-level errors
- Process message-level errors (unsupported messages)
- Process status-level errors
- Create `WaError` records
- Determine error level based on error code
- Log errors appropriately

**Methods**:
- `#call` - Process system errors
- `#process_message_error` - Handle message errors (private)
- `#process_status_error` - Handle status errors (private)
- `.process_message_error` - Class method for message errors
- `.process_status_error` - Class method for status errors

### 3. Updated Jobs

#### IngestWebhookJob
**Changes**:
- Now accepts `webhook_event_id` parameter
- Processes system-level errors before messages
- Processes statuses for delivery/read receipts

**New Logic**:
```ruby
# Process system/app/account-level errors
if value["errors"].present?
  Whatsapp::Processors::ErrorProcessor.new(value: value, webhook_event: webhook_event).call
end

# Process messages
Array(value["messages"]).to_a.each do |msg|
  Whatsapp::ProcessMessageJob.perform_later(value, msg, webhook_event&.id)
end

# Process message status updates
Array(value["statuses"]).to_a.each do |status|
  Whatsapp::ProcessStatusJob.perform_later(value, status, webhook_event&.id)
end
```

#### ProcessMessageJob
**Changes**:
- Now accepts `webhook_event_id` parameter
- Detects unsupported messages and message errors
- Early returns for error cases

**New Logic**:
```ruby
# Check for message-level errors (unsupported messages)
if msg["errors"].present? || msg["type"] == "unsupported"
  process_message_error(msg, webhook_event)
  return
end
```

#### ProcessStatusJob (NEW)
**Location**: `app/jobs/whatsapp/process_status_job.rb`

**Responsibilities**:
- Process status updates (sent, delivered, read, failed)
- Handle status-level errors
- Create `WaMessageStatusEvent` records
- Update message status

**Logic**:
```ruby
# Check for status-level errors
if status["errors"].present?
  Whatsapp::Processors::ErrorProcessor.process_status_error(status, webhook_event)
  return
end

# Create status event and update message
WaMessageStatusEvent.create!(...)
update_message_status(wa_message, status)
```

### 4. Updated Controller
**Location**: `app/controllers/webhooks_controller.rb`

**Changes**:
- Passes `webhook_event.id` to `IngestWebhookJob`

```ruby
webhook_event = WebhookEvent.create!(provider: "whatsapp", object_name: data["object"], payload: data)
Whatsapp::IngestWebhookJob.perform_later(data, webhook_event.id)
```

---

## Error Logging

### Log Format
All errors logged in JSON format with consistent structure:

```json
{
  "at": "whatsapp.error.{type}",
  "error_type": "system|message|status",
  "error_level": "error|warning|info",
  "error_code": 131047,
  "error_title": "Service unavailable",
  "error_message": "Service temporarily unavailable. Please retry your request",
  "provider_message_id": "wamid.123",  // if applicable
  "wa_message_id": 456                  // if applicable
}
```

### Log Levels
- **ERROR**: System errors, status errors
- **WARN**: Unsupported messages
- **INFO**: Informational errors (codes 0-99)

---

## Testing

### Test Files Created

1. **Error Handling Request Spec**
   - Location: `spec/requests/error_handling_spec.rb`
   - Tests all three error types
   - Verifies error record creation
   - Validates logging behavior
   - Confirms proper early returns

2. **WaError Factory**
   - Location: `spec/factories/wa_errors.rb`
   - Traits: `:system_error`, `:message_error`, `:status_error`, `:resolved`, `:warning`, `:info`

### Example Test Cases

```ruby
# System error test
it "creates WaError record for system errors" do
  expect {
    post "/ingest", params: system_error_payload.to_json,
         headers: { "Content-Type" => "application/json" }
    perform_enqueued_jobs
  }.to change { WaError.count }.by(1)

  error = WaError.last
  expect(error.error_type).to eq("system")
  expect(error.error_code).to eq(131047)
end

# Unsupported message test
it "does not process unsupported messages normally" do
  expect_any_instance_of(Whatsapp::Processors::TextProcessor).not_to receive(:call)

  post "/ingest", params: unsupported_message_payload.to_json
  perform_enqueued_jobs
end

# Status error test
it "does not create status event for failed status" do
  expect {
    post "/ingest", params: status_error_payload.to_json
    perform_enqueued_jobs
  }.not_to change { WaMessageStatusEvent.count }
end
```

---

## Usage Examples

### Query Unresolved Errors
```ruby
# Get all unresolved errors
WaError.unresolved.recent

# Get critical unresolved errors
WaError.critical.unresolved

# Get errors by type
WaError.by_type('system').unresolved
WaError.by_type('message').recent
```

### Resolve an Error
```ruby
error = WaError.find(123)
error.resolve!("Fixed API rate limit issue")
```

### Error Dashboard Query
```ruby
# Error summary
{
  total: WaError.count,
  unresolved: WaError.unresolved.count,
  critical: WaError.critical.unresolved.count,
  by_type: {
    system: WaError.by_type('system').count,
    message: WaError.by_type('message').count,
    status: WaError.by_type('status').count
  }
}
```

---

## Flow Diagrams

### System Error Flow
```
POST /ingest → WebhooksController
    ↓
Create WebhookEvent
    ↓
Enqueue IngestWebhookJob(payload, webhook_event_id)
    ↓
Detect value["errors"]
    ↓
ErrorProcessor.new(value, webhook_event).call
    ↓
Create WaError (type: 'system')
    ↓
Log ERROR
```

### Unsupported Message Flow
```
POST /ingest → IngestWebhookJob
    ↓
Enqueue ProcessMessageJob(value, msg, webhook_event_id)
    ↓
Detect msg["type"] == "unsupported" || msg["errors"]
    ↓
process_message_error(msg, webhook_event)
    ↓
ErrorProcessor.process_message_error(msg, wa_message, webhook_event)
    ↓
Create WaError (type: 'message')
    ↓
Log WARN
    ↓
RETURN (skip normal processing)
```

### Status Error Flow
```
POST /ingest → IngestWebhookJob
    ↓
Enqueue ProcessStatusJob(value, status, webhook_event_id)
    ↓
Detect status["errors"]
    ↓
ErrorProcessor.process_status_error(status, webhook_event)
    ↓
Create WaError (type: 'status')
    ↓
Log ERROR
    ↓
RETURN (skip status event creation)
```

---

## Migration Commands

```bash
# Run migration
bin/rails db:migrate

# Rollback if needed
bin/rails db:rollback
```

---

## Next Steps

1. **Update Existing Tests**: Update old test specs to use new job signatures with `webhook_event_id`
2. **Error Monitoring Dashboard**: Create admin interface to view and manage errors
3. **Alert System**: Add notifications for critical errors
4. **Error Analytics**: Track error patterns and trends
5. **Retry Mechanism**: Implement automatic retry for transient errors

---

## Related WhatsApp Documentation

- [Error Reference](https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components#errors)
- [Unsupported Messages](https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components#unsupported-object)
- [Status Object](https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components#statuses-object)
