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
    # 1) If we're still sticky, honor it (no LLM round-trip)
    if sticky_lane?(state)
      return RouterDecision.new(
        state["current_lane"],
        "continue_flow",
        0.95,
        remaining_sticky(state),
        [ "sticky" ]
      )
    end

    # 2) Build prompt with user message and state
    prompt = "User message: #{turn[:text]}\nState: #{compact_state_summary(state)}"

    # 3) Call LLM with structured schema output
    response = @client.with_instructions(system_prompt).with_schema(Schemas::RouterDecisionSchema).ask(prompt)

    # 4) Parse & clamp (with_schema returns response with .content as hash)
    result = response.content
    lane           = result["lane"]
    intent         = (result["intent"] || "general_info").to_s
    confidence     = clamp(result["confidence"].to_f, 0.0, 1.0)
    sticky_seconds = result["sticky_seconds"].to_i.clamp(0, 600)
    reasons        = Array(result["reasoning"]).map(&:to_s).first(5)


    RouterDecision.new(lane, intent, confidence, sticky_seconds, reasons)
  rescue StandardError => e
    # Fail-safe: default to info, low confidence
    RouterDecision.new("info", "general_info", 0.3, 0, [ "router_error: #{e.class}\n #{e.backtrace}" ])
  end

  # Optionally update stickiness in state from orchestrator after route()
  def update_sticky!(state:, lane:, seconds:)
    return if seconds <= 0
    state["current_lane"] = lane
    state["sticky_until"] = (@now.call + seconds).iso8601
  end

  private

  def sticky_lane?(state)
    until_ts = state["sticky_until"]
    lane     = state["current_lane"]
    until_ts && lane && Time.parse(until_ts) > @now.call
  rescue ArgumentError
    false
  end

  def remaining_sticky(state)
    until_ts = state["sticky_until"]
    return 0 unless until_ts
    [ Time.parse(until_ts) - @now.call, 0 ].max.to_i
  rescue ArgumentError
    0
  end

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
      sticky_until: state["sticky_until"],
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

    - sticky_seconds: How long to keep the user in this lane to avoid ping-pong (0-600 seconds, 0 if not needed)

    - reasoning: 1-3 short reasons for your decision (for observability)

    Consider the user's latest message, any interactive payload, and the compact STATE summary provided.
    Return ONLY your routing decision in the structured format. Do not answer the user's question.
    SYS
  end
end
