# frozen_string_literal: true

require "ruby_llm/schema"
require_relative "../../../lib/agent_config"

module Schemas
  # RubyLLM Schema for structured IntentRouter output
  # Ensures LLM responses match the RouterDecision data structure exactly
  #
  # Used by IntentRouter to get reliable, type-safe routing decisions from LLM
  # Lane options are loaded from config/agents.yml
  #
  # @example
  #   chat = RubyLLM.chat(provider: :openai, model: "gpt-4o")
  #   result = chat.with_schema(RouterDecisionSchema).ask(prompt)
  #   # => { "lane" => "commerce", "intent" => "start_order", ... }
  class RouterDecisionSchema < RubyLLM::Schema
    # Which agent domain should handle this turn
    string :lane,
           enum: AgentConfig.lanes,
           description: "Which agent domain should handle this turn"

    # Compact intent label for the chosen agent (e.g., business_hours, start_order, refund_request)
    string :intent,
           description: "Compact intent label for the chosen agent (e.g., business_hours, start_order, refund_request)"

    # Confidence score for the routing decision (0.0-1.0)
    number :confidence,
           description: "Confidence score for the routing decision (0.0-1.0)"

    # How long to pin to this lane to avoid ping-pong (0-600 seconds)
    integer :sticky_seconds,
            description: "How long to pin to this lane to avoid ping-pong (0-600 seconds)"

    # 1-3 short reasons for observability
    array :reasoning, of: :string,
          description: "1-3 short reasons for observability"
  end
end
