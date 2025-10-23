# frozen_string_literal: true

require_relative "router_decision"
require_relative "schemas/router_decision_schema"
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
        state.dig("meta", "current_lane"),
        "continue_flow",
        0.95,
        remaining_sticky(state),
        [ "sticky" ]
      )
    end

    # 2) Build prompt with user message and state
    prompt = "User message: #{turn[:text]}\nState: #{compact_state_summary(state)}"

    # 3) Call LLM with structured schema output
    result = @client.with_instructions(system_prompt).with_schema(Schemas::RouterDecisionSchema).ask(prompt)

    # 4) Parse & clamp (with_schema returns data directly, not wrapped in "arguments")
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

  # Optionally update stickiness in state.meta from orchestrator after route()
  def update_sticky!(state:, lane:, seconds:)
    return if seconds <= 0
    state["meta"]                 ||= {}
    state["meta"]["current_lane"] = lane
    state["meta"]["sticky_until"] = (@now.call + seconds).iso8601
  end

  private

  def sticky_lane?(state)
    until_ts = state.dig("meta", "sticky_until")
    lane     = state.dig("meta", "current_lane")
    until_ts && lane && Time.parse(until_ts) > @now.call
  rescue ArgumentError
    false
  end

  def remaining_sticky(state)
    until_ts = state.dig("meta", "sticky_until")
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
    meta = state.fetch("meta", {})
    slots = state.fetch("slots", {})
    commerce = state.fetch("commerce", {})
    {
      tenant_id: meta["tenant_id"],
      locale: meta["locale"],
      current_lane: meta["current_lane"],
      sticky_until: meta["sticky_until"],
      known_slots: {
        location_id: slots["location_id"],
        fulfillment: slots["fulfillment"],
        address_present: !slots["address"].nil?
      },
      commerce_state: commerce["state"],
      cart_items: commerce.dig("cart", "items")&.size || 0
    }.to_json
  end

  def system_prompt
    <<~SYS
    You are the Router for a WhatsApp business copilot. Analyze the user's message and session state to determine:

    - lane: Which agent domain should handle this turn [info, product, commerce, support]
      * info: General business information (hours, location, menu, services, FAQs)
      * product: Product-specific questions (details, attributes, categories, availability, comparisons)
      * commerce: Shopping and transactions (browse products, add to cart, checkout, order tracking)
      * support: Customer service issues (refunds, complaints, order problems, account help)

    - intent: A compact intent label meaningful to the chosen lane (e.g., business_hours, start_order, refund_request)

    - confidence: Your confidence in this routing decision (0.0 to 1.0)

    - sticky_seconds: How long to keep the user in this lane to avoid ping-pong (0-600 seconds, 0 if not needed)

    - reasoning: 1-3 short reasons for your decision (for observability)

    Consider the user's latest message, any interactive payload, and the compact STATE summary provided.
    Return ONLY your routing decision in the structured format. Do not answer the user's question.
    SYS
  end
end
