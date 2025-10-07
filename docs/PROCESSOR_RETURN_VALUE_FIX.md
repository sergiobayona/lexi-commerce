# Processor Return Value Fix

## Issue

All WhatsApp message processors were returning `msg_rec.body_text` (String) instead of the `msg_rec` (WaMessage) object itself. This caused the orchestration integration to fail with:

```
NoMethodError (undefined method 'id' for an instance of String)
NoMethodError (undefined method 'type_name' for an instance of String)
```

## Root Cause

When [ProcessMessageJob](app/jobs/whatsapp/process_message_job.rb) receives a message, it calls the appropriate processor based on message type. The processor creates/updates a `WaMessage` record, but was returning `msg_rec.body_text` (String) instead of `msg_rec` (WaMessage object).

Then `ProcessMessageJob` tried to pass this String to `OrchestrateTurnJob` which expects a WaMessage object, causing the error.

## Solution

Updated all message processors to return the `WaMessage` object instead of `body_text`:

### Files Modified

1. **[TextProcessor](app/services/whatsapp/processors/text_processor.rb:14)**
   ```ruby
   # Before:
   msg.body_text

   # After:
   msg
   ```

2. **[ButtonProcessor](app/services/whatsapp/processors/button_processor.rb:38)**
   ```ruby
   # Before:
   msg_rec.body_text

   # After:
   msg_rec
   ```

3. **[AudioProcessor](app/services/whatsapp/processors/audio_processor.rb:65)**
   ```ruby
   # Before:
   msg_rec.body_text

   # After:
   msg_rec
   ```

4. **[ContactProcessor](app/services/whatsapp/processors/contact_processor.rb:51)**
   ```ruby
   # Before:
   msg_rec.body_text

   # After:
   msg_rec
   ```

5. **[DocumentProcessor](app/services/whatsapp/processors/document_processor.rb:50)**
   ```ruby
   # Before:
   msg_rec.body_text

   # After:
   msg_rec
   ```

6. **[LocationProcessor](app/services/whatsapp/processors/location_processor.rb:47)**
   ```ruby
   # Before:
   msg_rec.body_text

   # After:
   msg_rec
   ```

## Message Flow After Fix

```
WebhooksController
  ↓
IngestWebhookJob
  ↓
ProcessMessageJob
  ↓
[Type]Processor.call → Returns WaMessage object ✅
  ↓
trigger_orchestration(wa_message) → Passes WaMessage object ✅
  ↓
OrchestrateTurnJob.perform_later(wa_message) → GlobalID serialization ✅
  ↓
TurnBuilder.build(wa_message) → Accesses wa_message.id, wa_message.type_name ✅
```

## Benefits

1. **Consistent Return Type**: All processors now return WaMessage objects
2. **Orchestration Compatible**: Can pass objects to OrchestrateTurnJob
3. **Type Safety**: Eliminates String vs WaMessage type confusion
4. **Future Extensibility**: Makes it easy to add more post-processing steps

## Testing

All tests pass after this fix:

```bash
# ProcessMessageJob tests
bundle exec rspec spec/jobs/whatsapp/process_message_job_spec.rb
# 5 examples, 0 failures

# Orchestration tests
bundle exec rspec spec/jobs/whatsapp/orchestrate_turn_job_spec.rb \
                  spec/services/whatsapp/turn_builder_spec.rb
# 28 examples, 0 failures
```

## Related Changes

This fix works in conjunction with:
- [GlobalID Refactoring](GLOBALID_REFACTORING.md) - Passing ActiveRecord objects to jobs
- [Orchestration Integration](../README_ORCHESTRATION.md) - Full conversation orchestration

## Migration Notes

If you create new message type processors:

```ruby
class MyNewProcessor < BaseProcessor
  def call
    # ... create/update message record
    msg_rec = upsert_message!(attrs)

    # ✅ Return the WaMessage object
    msg_rec

    # ❌ Don't return body_text or other attributes
    # msg_rec.body_text
  end
end
```

## Error Output Enhancement

Also added comprehensive error logging to [ProcessMessageJob](app/jobs/whatsapp/process_message_job.rb:34-53):

```ruby
rescue => e
  # Logs full backtrace to JSON log
  Rails.logger.error({
    at: "process_message.error",
    error: e.class.name,
    message: e.message,
    backtrace: e.backtrace
  }.to_json)

  # Outputs formatted error to STDOUT
  puts "\n" + "=" * 80
  puts "ERROR in ProcessMessageJob"
  puts "=" * 80
  puts "Exception: #{e.class.name}"
  puts "Message: #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.join("\n")
  puts "=" * 80 + "\n"

  raise # Re-raise for ActiveJob retry mechanism
end
```

**Benefits:**
- Full stack traces in both logs and console
- Easy debugging during development
- Preserves ActiveJob retry behavior

## Completion Status

- ✅ All 6 message type processors fixed
- ✅ Error handling enhanced with full backtraces
- ✅ All tests passing
- ✅ Orchestration integration working
- ✅ Documentation complete

**Processor return value fix complete!** 🎉
