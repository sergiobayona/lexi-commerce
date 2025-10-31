# Orchestration System - Quick Start

## Overview

Conversation orchestration is **always active** for text and button messages. Every inbound WhatsApp message flows through the orchestration pipeline automatically.

## How It Works

```
WhatsApp Message (text/button)
      ↓
ProcessMessageJob → saves WaMessage to database
      ↓
OrchestrateTurnJob → automatically triggered
      ↓
State::Controller → manages conversation
      ├─→ Loads/creates session in Redis
      ├─→ Routes to appropriate lane (info/commerce/support)
      ├─→ Dispatches to agent (InfoAgent, etc.)
      └─→ Updates session state
            ↓
         Logs agent responses (not sent yet - Phase 2)
```

## Current Status

### ✅ What's Active
- **Automatic orchestration** for text and button messages
- **Session management** in Redis (24-hour TTL)
- **Intent routing** (default routing, LLM integration pending)
- **InfoAgent** with Spanish responses
- **State tracking** with dialogue history
- **Idempotency** handling for duplicate webhooks
- **Distributed locking** to prevent race conditions

### ❌ What's NOT Active Yet
- Sending responses back to WhatsApp (responses are logged only)
- LLM-based intent classification
- Full Commerce/Support agent functionality

## Testing

### 1. Send a WhatsApp Message
Send any text message to your WhatsApp Business number.

### 2. Check Logs
```bash
tail -f log/development.log | grep orchestrat
```

**Expected output:**
```json
{"at":"process_message.orchestration_triggered","wa_message_id":123,"message_type":"text"}
{"at":"orchestrate_turn.completed","success":true,"lane":"info","messages_count":1}
```

### 3. Inspect Redis Session
```ruby
# In Rails console
redis = Redis.new(url: ENV['REDIS_URL'])

# List all sessions
redis.keys("session:*")

# View a session
session_key = redis.keys("session:*").first
state = JSON.parse(redis.get(session_key))

# Check dialogue history
state["dialogue"]["turns"]
# => [{"role"=>"user", "text"=>"Hola", "timestamp"=>"2025-10-02T10:00:00Z"}]

# Check current lane
state["meta"]["current_lane"]
# => "info"
```

### 4. Run Tests
```bash
# Test orchestration job
rspec spec/jobs/whatsapp/orchestrate_turn_job_spec.rb

# Test turn building
rspec spec/services/whatsapp/turn_builder_spec.rb

# Test State module
rspec spec/services/state/
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379/1` | Redis connection for session state |

### Redis Keys

| Pattern | TTL | Purpose |
|---------|-----|---------|
| `session:{tenant_id}:{wa_id}` | 24h | Session state |
| `session:{tenant_id}:{wa_id}:lock` | 30s | Distributed lock |
| `turn:processed:{message_id}` | 1h | Idempotency tracking |
| `orchestrated:{message_id}` | 1h | Prevents duplicate orchestration |

## Message Types

Orchestration is triggered for:
- ✅ **text** messages
- ✅ **button** responses (interactive messages)

Not yet orchestrated (stored but skipped):
- ⏸️ audio (waiting for transcription integration)
- ⏸️ location, contacts, documents
- ⏸️ image, video, sticker

## Monitoring

### Success Metrics
```bash
# Count orchestrated messages today
grep "orchestrate_turn.completed" log/development.log | grep $(date +%Y-%m-%d) | wc -l

# Check success rate
grep "orchestrate_turn.completed" log/development.log | grep "success\":true" | wc -l
```

### Lane Distribution
```ruby
# In Rails console
redis = Redis.new(url: ENV['REDIS_URL'])
sessions = redis.keys("session:*").map { |k| JSON.parse(redis.get(k)) }
sessions.map { |s| s.dig("meta", "current_lane") }.tally
# => {"info"=>15, "commerce"=>2, "support"=>1}
```

### Common Issues

**Issue: Orchestration not happening**
- Check: Is message type "text" or "button"?
- Check: Is ProcessMessageJob running?
- Check: Redis connection working?

**Issue: Session state not persisting**
- Check: REDIS_URL environment variable
- Check: Redis server running (`redis-cli ping`)
- Check: Redis memory limits

**Issue: Errors in logs**
- Check: State validation errors (corrupted session)
- Check: Agent errors (InfoAgent implementation)
- Check: Lock contention (concurrent processing)

## Next Steps

### Phase 2: Response Sending
To actually send messages back to users:

1. Implement `Whatsapp::MessageSender` service
2. Create `Whatsapp::SendResponseJob`
3. Uncomment sending code in `OrchestrateTurnJob` (line 38-41)
4. Configure WhatsApp Business API credentials

### Phase 3: Enhanced Routing
- Connect IntentRouter to OpenAI/Anthropic
- Train routing prompts
- Monitor classification accuracy

### Phase 4: Agent Expansion
- Build out CommerceAgent (cart, orders, payments)
- Build out SupportAgent (tickets, FAQ, escalation)
- Add more intents and flows

## Architecture Details

For complete architecture documentation, see:
- [ORCHESTRATION.md](ORCHESTRATION.md) - Full system documentation
- `app/services/state/` - State management components
- `app/services/agents/` - Agent implementations
- `spec/services/state/` - Test examples

## Support

Questions? Check:
1. Logs: `tail -f log/development.log | grep orchestrat`
2. Redis: `redis-cli -n 1` (if using database 1)
3. Tests: `rspec spec/services/state/controller_spec.rb --format doc`
4. State module code: `app/services/state/*.rb`
