# frozen_string_literal: true

require_relative "router_decision"
require_relative "schemas/router_decision_schema"
require_relative "../../lib/agent_config"
require "ruby_llm"

class IntentRouter
  def initialize
    @client = RubyLLM.chat(model: "gpt-4o-mini")
    @now    = -> { Time.zone.now }
  end

  # turn: { text:, payload:, timestamp:, tenant_id:, wa_id:, message_id: }
  # state: Contract-shaped session hash
  def route(turn:, state:)
    # Build prompt with user message and state
    prompt = "User message: #{turn[:text]}\nState: #{compact_state_summary(state)}"

    # Call LLM with structured schema output
    response = @client.with_instructions(system_prompt).with_schema(Schemas::RouterDecisionSchema).ask(prompt)

    # Parse & clamp (with_schema returns response with .content as hash)
    result = response.content
    lane           = result["lane"]
    intent         = (result["intent"] || "general_info").to_s
    confidence     = clamp(result["confidence"].to_f, 0.0, 1.0)
    reasons        = Array(result["reasoning"]).map(&:to_s).first(5)

    RouterDecision.new(lane, intent, confidence, reasons)
  rescue StandardError => e
    # Fail-safe: default to info, low confidence
    RouterDecision.new("info", "general_info", 0.3, [ "router_error: #{e.class}\n #{e.backtrace}" ])
  end

  private

  def clamp(v, lo, hi) = [ [ v, lo ].max, hi ].min

  # Provide payload as a hint, but let the LLM decide
  def payload_hint(payload)
    return [] unless payload
    [ { role: "user", content: "PAYLOAD: #{payload}" } ]
  end

  # Keep the state snapshot tiny and privacy-safe
  def compact_state_summary(state)
    {
      tenant_id: state["tenant_id"],
      locale: state["locale"],
      current_lane: state["current_lane"],
      location_id: state["location_id"],
      fulfillment: state["fulfillment"],
      address_present: !state["address"].nil?,
      commerce_state: state["commerce_state"],
      cart_items_count: state["cart_items"]&.size || 0
    }.to_json
  end

  def system_prompt
    # Generate lane descriptions dynamically from config
    lane_descriptions = AgentConfig.lane_descriptions.map do |lane, description|
      "      * #{lane}: #{description}"
    end.join("\n")

    <<~SYS
    You are the Router for a WhatsApp business copilot. Analyze the user's message and session state to determine:

    - lane: Which agent domain should handle this turn [#{AgentConfig.lanes.join(", ")}]
    #{lane_descriptions}

    - intent: A compact intent label meaningful to the chosen lane (e.g., business_hours, start_order, refund_request)

    - confidence: Your confidence in this routing decision (0.0 to 1.0)

    - reasoning: 1-3 short reasons for your decision (for observability)

    Consider the user's latest message, any interactive payload, and the compact STATE summary provided.
    Return ONLY your routing decision in the structured format. Do not answer the user's question.
    SYS
  end
end
