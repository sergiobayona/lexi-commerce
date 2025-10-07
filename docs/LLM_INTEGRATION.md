# LLM Integration for Intent Routing

## Overview

The IntentRouter now uses RubyLLM with structured output to provide intelligent, LLM-powered intent classification for WhatsApp messages. This replaces the stubbed implementation with real AI-powered routing.

## Architecture

### Components

1. **RouterDecisionSchema** (`app/services/schemas/router_decision_schema.rb`)
   - RubyLLM::Schema definition for structured output
   - Guarantees exact schema matching from LLM responses
   - Fields: lane, intent, confidence, sticky_seconds, reasoning

2. **LLMClient** (`app/services/intent_router.rb`)
   - RubyLLM-backed client with multi-provider support
   - Graceful fallback when LLM disabled or fails
   - Configurable via environment variables

3. **IntentRouter** (`app/services/intent_router.rb`)
   - Uses LLMClient for routing decisions
   - Maintains sticky session logic
   - Fallback to rule-based routing on errors

## Configuration

### Environment Variables

```bash
# Enable/disable LLM routing
LLM_ROUTING_ENABLED=true

# Provider selection (openai, anthropic, gemini)
LLM_PROVIDER=openai

# Model configuration
LLM_MODEL=gpt-4o-mini

# Performance tuning
LLM_TIMEOUT=0.9
LLM_TEMPERATURE=0.3

# API Keys (provider-specific)
OPENAI_API_KEY=sk-...your-key-here
ANTHROPIC_API_KEY=your-key-here
GOOGLE_AI_API_KEY=your-key-here
```

### Recommended Configuration

**Production:**
```bash
LLM_ROUTING_ENABLED=true
LLM_PROVIDER=openai
LLM_MODEL=gpt-4o-mini
LLM_TEMPERATURE=0.3
LLM_TIMEOUT=0.9
OPENAI_API_KEY=sk-...
```

**Development:**
```bash
LLM_ROUTING_ENABLED=false  # Use fallback for faster testing
```

## Provider Support

### OpenAI (Recommended)
- **Models**: gpt-4o, gpt-4o-mini
- **Structured Output**: Full support with guaranteed schema matching
- **Cost**: $0.150 per 1M input tokens (gpt-4o-mini)
- **Speed**: ~500-800ms average response time

### Gemini
- **Models**: gemini-1.5-pro, gemini-1.5-flash
- **Structured Output**: Full support
- **Cost**: Competitive pricing
- **Speed**: ~600-1000ms average response time

### Anthropic
- **Models**: claude-3-5-sonnet-20241022
- **Structured Output**: Limited support
- **Note**: Not recommended for this use case

## Usage

### Basic Usage

```ruby
# Automatic usage via IntentRouter
router = IntentRouter.new
decision = router.route(turn: turn_data, state: session_state)

# decision.lane => "commerce"
# decision.intent => "start_order"
# decision.confidence => 0.85
# decision.sticky_seconds => 120
# decision.reasons => ["User mentioned ordering", "Commerce keywords detected"]
```

### Direct LLMClient Usage

```ruby
client = LLMClient.new
result = client.call(
  system: "Route this message to appropriate lane",
  messages: [{ role: "user", content: "I want to order pizza" }]
)

# result => {
#   "arguments" => {
#     "lane" => "commerce",
#     "intent" => "start_order",
#     "confidence" => 0.85,
#     "sticky_seconds" => 120,
#     "reasoning" => ["User wants to order", "Commerce keywords"]
#   }
# }
```

## Testing

### Running Tests

```bash
# Unit tests for LLMClient
rspec spec/services/llm_client_spec.rb

# Schema validation tests
rspec spec/services/schemas/router_decision_schema_spec.rb

# Integration test (no database required)
ruby test_llm_integration.rb
```

### Test Coverage

- ✅ Schema definition and structure
- ✅ LLMClient initialization
- ✅ Fallback behavior when disabled
- ✅ LLM call with structured output
- ✅ Error handling and recovery
- ✅ IntentRouter integration

## Cost Estimation

### OpenAI GPT-4o-mini

**Per Routing Decision:**
- Input: ~100 tokens (system prompt + user message + state summary)
- Output: ~50 tokens (structured response)
- Cost: ~$0.000015 per decision

**Monthly Estimates:**
- 10,000 messages: ~$0.15
- 100,000 messages: ~$1.50
- 1,000,000 messages: ~$15.00

## Performance

### Response Times

- **LLM Call**: 500-1000ms (provider dependent)
- **Fallback**: <1ms (instant)
- **Total Routing**: <1s with LLM, <5ms without

### Optimization Tips

1. **Use gpt-4o-mini** for best cost/performance balance
2. **Set temperature=0.3** for deterministic routing
3. **Keep timeout<1s** to maintain responsiveness
4. **Enable fallback** for high availability

## Monitoring

### Key Metrics

1. **Routing Accuracy**
   - Lane selection correctness
   - Intent classification precision
   - Confidence score distribution

2. **Performance**
   - P50/P95/P99 latency
   - Timeout rate
   - Fallback activation rate

3. **Cost**
   - Token usage per decision
   - Monthly spend tracking
   - Cost per conversation

### Logging

Add to IntentRouter for observability:

```ruby
Rails.logger.info({
  at: "intent_router.llm_decision",
  lane: decision.lane,
  intent: decision.intent,
  confidence: decision.confidence,
  reasoning: decision.reasons,
  llm_enabled: LLMClient::ENABLED,
  response_time_ms: elapsed_time
})
```

## Error Handling

### Graceful Degradation

1. **LLM Disabled**: Falls back to rule-based routing immediately
2. **API Timeout**: Catches timeout, returns fallback response
3. **API Error**: Logs error, returns fallback response
4. **Invalid Response**: Validates schema, uses fallback if invalid

### Fallback Response

```ruby
{
  "lane" => "info",
  "intent" => "general_info",
  "confidence" => 0.5,
  "sticky_seconds" => 60,
  "reasoning" => ["LLM routing disabled or failed, using fallback"]
}
```

## Troubleshooting

### Common Issues

**Issue: LLM not being called**
- Check `LLM_ROUTING_ENABLED=true`
- Verify API key is set correctly
- Check Rails logs for initialization errors

**Issue: Slow response times**
- Reduce `LLM_TIMEOUT` value
- Switch to faster model (gpt-4o-mini)
- Consider caching for common queries

**Issue: High costs**
- Review token usage per decision
- Optimize system prompt length
- Reduce state summary verbosity
- Consider switching to cheaper model

**Issue: Inaccurate routing**
- Fine-tune system prompt
- Adjust temperature (lower = more deterministic)
- Add more examples to prompt
- Review confidence scores

## Future Enhancements

- [ ] Prompt engineering and fine-tuning
- [ ] Caching for common queries
- [ ] A/B testing different prompts
- [ ] Routing accuracy metrics dashboard
- [ ] Cost optimization analysis
- [ ] Custom fine-tuned models
- [ ] Multi-shot prompting for edge cases

## References

- [RubyLLM Documentation](https://rubyllm.com/)
- [RubyLLM Schema](https://github.com/danielfriis/ruby_llm-schema)
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs)
- [ORCHESTRATION.md](./ORCHESTRATION.md) - Overall orchestration system
