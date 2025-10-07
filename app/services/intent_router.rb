# frozen_string_literal: true

require_relative "router_decision"
require_relative "schemas/router_decision_schema"
require "ruby_llm"

# ======================================
# RubyLLM-backed LLM client for intent routing
# ======================================
class LLMClient
  # Configuration for LLM provider and model
  # Defaults to OpenAI GPT-4o for best structured output support
  PROVIDER = ENV.fetch("LLM_PROVIDER", "openai").to_sym
  MODEL = ENV.fetch("LLM_MODEL", "gpt-4o-mini")
  TIMEOUT = ENV.fetch("LLM_TIMEOUT", "0.9").to_f
  TEMPERATURE = ENV.fetch("LLM_TEMPERATURE", "0.3").to_f

  # Feature flag to enable/disable LLM routing
  # Falls back to rule-based routing when disabled
  ENABLED = ENV.fetch("LLM_ROUTING_ENABLED", "false") == "true"

  def initialize
    @client = RubyLLM.chat(provider: PROVIDER, model: MODEL) if ENABLED
  end

  # Call LLM with structured output schema for intent routing
  #
  # @param system [String] System prompt for routing instructions
  # @param messages [Array<Hash>] Conversation messages
  # @param tools [Array] Unused (for backward compatibility)
  # @param tool_choice [String] Unused (for backward compatibility)
  # @param timeout [Float] Request timeout in seconds
  #
  # @return [Hash] Arguments hash matching RouterDecisionSchema structure
  def call(system:, messages:, tools: nil, tool_choice: nil, timeout: TIMEOUT)
    unless ENABLED
      return fallback_response
    end

    # Convert messages to simple prompt format
    # RubyLLM handles system prompts internally
    user_messages = messages.select { |m| m[:role] == "user" }
                           .map { |m| m[:content] }
                           .join("\n")

    prompt = "#{system}\n\n#{user_messages}"

    # Request structured output using schema
    response = @client
      .with_schema(Schemas::RouterDecisionSchema)
      .with_options(temperature: TEMPERATURE, timeout: timeout)
      .ask(prompt)

    # RubyLLM returns the parsed hash directly
    { "arguments" => response }
  rescue StandardError => e
    Rails.logger.error("LLM routing failed: #{e.class} - #{e.message}")
    { "arguments" => fallback_response["arguments"] }
  end

  private

  # Fallback to rule-based routing when LLM is disabled or fails
  def fallback_response
    {
      "arguments" => {
        "lane" => "info",
        "intent" => "general_info",
        "confidence" => 0.5,
        "sticky_seconds" => 60,
        "reasoning" => [ "LLM routing disabled or failed, using fallback" ]
      }
    }
  end
end

class IntentRouter
  def initialize(client: LLMClient.new, now: -> { Time.now.utc })
    @client = client
    @now    = now
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

    # 2) Build LLM function-call request
    tools = [ route_tool_schema ]
    sys   = system_prompt
    msgs  = [
      { role: "system", content: sys },
      { role: "user",   content: turn[:text].to_s },
      { role: "assistant", content: "STATE:" + compact_state_summary(state) },
      *payload_hint(turn[:payload])
    ]

    # 3) Call LLM (tool/function required)
    result = @client.call(system: sys, messages: msgs, tools: tools, tool_choice: "required", timeout: 0.9)

    # 4) Parse & clamp
    args = (result || {})["arguments"] || {}
    lane           = normalize_lane(args["lane"])
    intent         = (args["intent"] || "general_info").to_s
    confidence     = clamp(args["confidence"].to_f, 0.0, 1.0)
    sticky_seconds = args["sticky_seconds"].to_i.clamp(0, 600)
    reasons        = Array(args["reasoning"]).map(&:to_s).first(5)

    # 5) Fallbacks if LLM returned junk
    lane ||= default_lane_from_context(state)

    RouterDecision.new(lane, intent, confidence, sticky_seconds, reasons)
  rescue StandardError => e
    # Fail-safe: default to info, low confidence
    RouterDecision.new("info", "general_info", 0.3, 0, [ "router_error: #{e.class}" ])
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

  def default_lane_from_context(state)
    (state.dig("meta", "current_lane") || "info").to_s
  end

  def normalize_lane(x)
    case x.to_s.downcase
    when "commerce", "buy", "order" then "commerce"
    when "support", "help"          then "support"
    when "info", ""                 then "info"
    else nil
    end
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

  # Tool/function schema the LLM must call
  def route_tool_schema
    {
      "type" => "function",
      "function" => {
        "name" => "route",
        "description" => "Choose lane and intent for this turn. Consider message, payload, and state summary. Return confidence and a short reasoning list. Suggest a sticky window in seconds for continuity.",
        "parameters" => {
          "type" => "object",
          "properties" => {
            "lane" => {
              "type" => "string",
              "enum" => [ "info", "commerce", "support" ],
              "description" => "Which agent domain should handle this turn?"
            },
            "intent" => {
              "type" => "string",
              "description" => "Compact intent label for the chosen agent (e.g., business_hours, start_order, refund_request)."
            },
            "confidence" => {
              "type" => "number",
              "minimum" => 0, "maximum" => 1
            },
            "sticky_seconds" => {
              "type" => "integer",
              "minimum" => 0, "maximum" => 600,
              "description" => "How long to pin to this lane to avoid ping-pong."
            },
            "reasoning" => {
              "type" => "array",
              "items" => { "type" => "string" },
              "description" => "1–3 short reasons for observability."
            }
          },
          "required" => [ "lane", "intent", "confidence" ]
        }
      }
    }
  end

  def system_prompt
    <<~SYS
    You are the Router for a WhatsApp SMB copilot. Your job is ONLY to choose:
    - lane: one of [info, commerce, support]
    - intent: a compact label meaningful to that lane
    - confidence: 0..1
    - sticky_seconds: how long to keep the user in this lane (0 if not needed)
    Consider:
      * The user's latest message
      * Any interactive payload
      * A compact STATE summary (no PII)
    STRICTLY return a function call to `route` with your decision. Do not answer the user.
    SYS
  end
end
