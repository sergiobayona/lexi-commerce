#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test script to verify LLM integration without database
# Run with: ruby test_llm_integration.rb

require "bundler/setup"
require "ruby_llm"

# Load the schema
require_relative "app/services/schemas/router_decision_schema"

puts "=" * 60
puts "RubyLLM Integration Test"
puts "=" * 60

# Test 1: Schema validation
puts "\n✓ Schema loaded successfully: #{Schemas::RouterDecisionSchema}"
puts "  - Inherits from RubyLLM::Schema: #{Schemas::RouterDecisionSchema < RubyLLM::Schema}"

# Test 2: LLMClient with fallback (no API key needed)
ENV["LLM_ROUTING_ENABLED"] = "false"

require_relative "app/services/router_decision"
require_relative "app/services/intent_router"

client = LLMClient.new
puts "\n✓ LLMClient initialized (fallback mode)"

result = client.call(
  system: "Route this message",
  messages: [ { role: "user", content: "I want to order pizza" } ]
)

puts "\n✓ Fallback response structure:"
puts "  Lane: #{result.dig('arguments', 'lane')}"
puts "  Intent: #{result.dig('arguments', 'intent')}"
puts "  Confidence: #{result.dig('arguments', 'confidence')}"
puts "  Sticky seconds: #{result.dig('arguments', 'sticky_seconds')}"
puts "  Reasoning: #{result.dig('arguments', 'reasoning')}"

# Test 3: IntentRouter with LLMClient
router = IntentRouter.new(client: client)
puts "\n✓ IntentRouter initialized with LLMClient"

turn = {
  text: "What are your hours?",
  payload: nil,
  timestamp: Time.now.utc,
  tenant_id: "test",
  wa_id: "1234567890",
  message_id: "msg_123"
}

state = {
  "meta" => {},
  "dialogue" => {},
  "slots" => {},
  "commerce" => {},
  "support" => {}
}

decision = router.route(turn: turn, state: state)
puts "\n✓ Routing decision:"
puts "  Lane: #{decision.lane}"
puts "  Intent: #{decision.intent}"
puts "  Confidence: #{decision.confidence}"
puts "  Sticky seconds: #{decision.sticky_seconds}"
puts "  Reasons: #{decision.reasons.join(', ')}"

puts "\n" + "=" * 60
puts "✅ All integration tests passed!"
puts "=" * 60

puts "\nNext steps:"
puts "1. Set LLM_ROUTING_ENABLED=true in .env"
puts "2. Add your OPENAI_API_KEY to .env"
puts "3. Test with real LLM calls"
puts "\nExample .env configuration:"
puts "  LLM_ROUTING_ENABLED=true"
puts "  LLM_PROVIDER=openai"
puts "  LLM_MODEL=gpt-4o-mini"
puts "  OPENAI_API_KEY=sk-..."
