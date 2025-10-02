# Conversation Orchestration System

## Overview

The orchestration system manages stateful WhatsApp conversations using a multi-agent architecture with intelligent routing, session management, and lane-based specialization.

## Architecture

```
WhatsApp Message
      ↓
ProcessMessageJob (saves to DB)
      ↓
OrchestrateTurnJob (if ENABLE_ORCHESTRATION=true)
      ↓
State::Controller
      ├─→ IntentRouter (determines lane + intent)
      ├─→ AgentRegistry (selects agent)
      └─→ InfoAgent/CommerceAgent/SupportAgent
            ↓
         State Updates + Messages (logged in Phase 1)
            ↓
         (Phase 2+: Send responses via WhatsApp API)
```

## Components

### State::Controller
**Location**: `app/services/state/controller.rb`

Orchestrates conversation turns with:
- Session lifecycle management (create/load/validate)
- Distributed locking (prevents concurrent processing)
- Idempotency (handles webhook retries)
- Intent routing
- Agent dispatch
- State updates with optimistic locking
- Lane handoffs

### IntentRouter
**Location**: `app/services/intent_router.rb`

Determines which agent should handle a message:
- Uses LLM for intent classification (future)
- Returns: lane, intent, confidence, sticky_seconds
- Sticky sessions prevent ping-pong between lanes

**Lanes:**
- `info` - General information, FAQs, business hours
- `commerce` - Shopping, orders, payments
- `support` - Customer service, issues, escalation

### Agents
**Location**: `app/services/agents/`

Specialized handlers for each lane:

#### InfoAgent
- Handles general information queries
- Business hours, locations, FAQs
- Initiates handoffs to commerce/support

#### CommerceAgent (Stub)
- Shopping cart management
- Order placement
- Payment processing

#### SupportAgent (Stub)
- Customer service
- Issue tracking
- Human escalation

### State Management
**Location**: `app/services/state/`

Session state stored in Redis with:
- **Contract**: Schema definition and validation
- **Builder**: Session creation and hydration
- **Validator**: Structure and semantic validation
- **Upcaster**: Schema version migration
- **Patcher**: Atomic updates with optimistic locking

**State Structure:**
```ruby
{
  "version" => 3,
  "meta" => {
    "tenant_id" => "phone_number_id",
    "wa_id" => "whatsapp_user_id",
    "current_lane" => "info",
    "sticky_until" => "2025-10-03T10:00:00Z"
  },
  "dialogue" => {
    "turns" => [],
    "last_user_msg_id" => "msg_123"
  },
  "slots" => {},      # Extracted entities
  "commerce" => {},   # Shopping state
  "support" => {}     # Support tickets
}
```

## Phase 1: Foundation (Current)

### What's Implemented
✅ Complete orchestration infrastructure
✅ State management with Redis
✅ Intent routing (stubbed)
✅ InfoAgent with basic responses
✅ Turn construction from WaMessage
✅ Feature flag for safe activation
✅ Comprehensive logging

### What's NOT Active
❌ Actual response sending (logged only)
❌ LLM-based intent routing (uses defaults)
❌ Commerce/Support functionality
❌ Real WhatsApp message sending

### Enabling Orchestration

**1. Set environment variable:**
```bash
export ENABLE_ORCHESTRATION=true
```

**2. Restart workers:**
```bash
mise run worker  # or your worker restart command
```

**3. Monitor logs:**
```bash
tail -f log/development.log | grep orchestrat
```

**Expected log output:**
```json
{
  "at": "process_message.orchestration_triggered",
  "wa_message_id": 123,
  "provider_message_id": "wamid.XXX",
  "message_type": "text"
}

{
  "at": "orchestrate_turn.completed",
  "success": true,
  "lane": "info",
  "messages_count": 1,
  "state_version": 4
}
```

### Testing Orchestration

**1. Send a text message via WhatsApp**

**2. Check that OrchestrateTurnJob runs:**
```ruby
# In Rails console
SolidQueue::Job.where(class_name: "Whatsapp::OrchestrateTurnJob").last

# Check Redis for session state
redis = Redis.new(url: ENV['REDIS_URL'])
redis.keys("session:*")
redis.get("session:PHONE_NUMBER_ID:USER_WA_ID")
```

**3. Review orchestration logs:**
```bash
grep "orchestrate_turn" log/development.log
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_ORCHESTRATION` | `false` | Enable conversation orchestration |
| `REDIS_URL` | `redis://localhost:6379/1` | Redis connection for state |

### Redis Keys

| Pattern | TTL | Purpose |
|---------|-----|---------|
| `session:{tenant}:{wa_id}` | 24h | Session state |
| `session:{tenant}:{wa_id}:lock` | 30s | Distributed lock |
| `turn:processed:{msg_id}` | 1h | Idempotency |
| `orchestrated:{msg_id}` | 1h | Prevents duplicate orchestration |

## Message Flow Example

```
1. User sends: "Hola"

2. ProcessMessageJob
   - Saves to wa_messages table
   - Triggers OrchestrateTurnJob (if enabled)

3. OrchestrateTurnJob
   - Builds turn: {tenant_id, wa_id, message_id, text: "Hola", ...}
   - Calls State::Controller.handle_turn(turn)

4. State::Controller
   - Acquires session lock
   - Loads/creates session state
   - Routes to "info" lane
   - Calls InfoAgent.handle(turn, state, intent: "general_info")

5. InfoAgent
   - Returns greeting message
   - Updates state with interaction timestamp

6. State::Controller
   - Applies state patch (increments version)
   - Logs result
   - Releases lock

7. Phase 1: Logs messages (doesn't send)
   Phase 2+: Enqueues SendResponseJob
```

## Monitoring & Debugging

### Key Metrics to Watch

**Success Rate:**
```sql
-- In Rails console or monitoring
orchestration_logs = Rails.logger.filter(at: "orchestrate_turn.completed")
success_rate = orchestration_logs.count { |l| l[:success] } / orchestration_logs.count.to_f
```

**Lane Distribution:**
```ruby
# Check which lanes are being used
redis.keys("session:*").map { |k| JSON.parse(redis.get(k))["meta"]["current_lane"] }.tally
```

**Lock Contention:**
```bash
grep "lock" log/development.log | grep "failed"
```

### Common Issues

**Issue: Orchestration not triggering**
- Check `ENABLE_ORCHESTRATION=true`
- Verify message type is "text" or "button"
- Check logs for "orchestration_triggered"

**Issue: Session state not persisting**
- Check Redis connection
- Verify REDIS_URL is correct
- Check Redis memory limits

**Issue: Version conflicts**
- Check for concurrent message processing
- Review lock acquisition logs
- Increase lock timeout if needed

## Next Steps: Phase 2

### Planned Enhancements
1. **WhatsApp Response Sending**
   - Implement SendResponseJob
   - Connect to WhatsApp Business API
   - Handle rate limiting

2. **LLM Integration**
   - Connect IntentRouter to OpenAI/Anthropic
   - Fine-tune routing prompts
   - Monitor routing accuracy

3. **Commerce Agent**
   - Shopping cart functionality
   - Product catalog integration
   - Order placement

4. **Support Agent**
   - Ticket creation
   - FAQ database
   - Human handoff workflow

## Development

### Adding a New Agent

1. **Create agent class:**
```ruby
# app/services/agents/my_agent.rb
module Agents
  class MyAgent < BaseAgent
    def handle(turn:, state:, intent:)
      respond(
        messages: text_message("Response text"),
        state_patch: { "my_data" => { "key" => "value" } }
      )
    end
  end
end
```

2. **Register in AgentRegistry:**
```ruby
# app/services/agent_registry.rb
def instantiate_agent(lane)
  case lane
  when "my_lane"
    Agents::MyAgent.new
  # ...
  end
end
```

3. **Update IntentRouter:**
```ruby
# Add "my_lane" to routing logic
```

### Testing

```bash
# Run State module tests
rspec spec/services/state/

# Run orchestration tests
rspec spec/jobs/whatsapp/orchestrate_turn_job_spec.rb

# Integration test
rspec spec/requests/whatsapp_orchestration_spec.rb
```

## Support

For questions or issues:
1. Check logs: `log/development.log`
2. Inspect Redis: `redis-cli -n 1`
3. Review test suite: `spec/services/state/`
4. Consult State module docs: `app/services/state/*.rb`
