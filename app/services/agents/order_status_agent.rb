# frozen_string_literal: true

module Agents
  # OrderStatusAgent handles order tracking, shipping updates, and delivery ETAs
  # Uses RubyLLM with specialized order tools and verification state management
  #
  # Responsibilities:
  # - Verify customer identity before providing order information
  # - Query Order Management System (OMS) for order details
  # - Provide shipping status and tracking information
  # - Deliver estimated delivery dates
  # - Handle order-related inquiries
  class OrderStatusAgent < BaseAgent
    attr_reader :chat

    def initialize(model: "gpt-4o-mini")
      @model = model
      @state_holder = { state: nil }  # Holds current state for accessor injection
      @chat = RubyLLM.chat(model: @model)

      # Tools will be registered in handle() after state is available
      setup_tool_monitoring
    end

    def handle(turn:, state:, intent:)
      question = turn[:text]
      Rails.logger.info "[OrderStatusAgent] Handling intent '#{intent}' with question: #{question}"

      # Store state for accessor injection
      @state_holder[:state] = state

      # Register tools with state accessors
      register_tools_with_state

      # Build context from order state and verification status
      context = build_context(state)

      # Use RubyLLM chat with tools to get the response
      full_question = context.empty? ? question : "#{context}\n\nUser question: #{question}"
      response = @chat.ask(full_question)

      # Build state patch
      state_patch = {
        "order" => {
          "last_interaction" => Time.now.utc.iso8601
        },
        "dialogue" => {
          "last_order_query" => question
        }
      }

      # Return structured AgentResponse
      respond(
        messages: text_message(response),
        state_patch: state_patch
      )
    rescue StandardError => e
      handle_error(e, "OrderStatusAgent")
    end

    private

    def register_tools_with_state
      # Create accessor providers that will be called by tools
      order_accessor_provider = -> { State::Accessors::OrderAccessor.new(@state_holder[:state]) }
      state_provider = -> { @state_holder[:state] }

      # Get tools with injected accessors
      @tools = Tools::OrderRegistry.all(
        order_accessor_provider: order_accessor_provider,
        state_provider: state_provider
      )

      # Register all tools (clears previous registration)
      @tools.each { |tool| @chat.with_tool(tool) }

      # Set/update system instructions
      @chat.with_instructions(system_instructions)
    end

    def setup_tool_monitoring
      @chat.on_tool_call do |tool_call|
        Rails.logger.info "[OrderStatusAgent] Tool invoked: #{tool_call.name} with arguments: #{tool_call.arguments}"
      end
    end

    def build_context(state)
      context_parts = []

      # Order verification context
      order_accessor = State::Accessors::OrderAccessor.new(state)
      summary = order_accessor.summary

      if summary[:verified]
        context_parts << "Customer verified: Yes (at #{summary[:verified_at]})"
      elsif summary[:customer_verified]
        context_parts << "Customer phone verified: Yes (can access orders)"
      else
        context_parts << "Customer verified: No (verification required for order access)"
      end

      # Last order context
      if summary[:last_order_id]
        context_parts << "Last order viewed: #{summary[:last_order_id]}"
      end

      # Lookup history
      if summary[:lookup_count] > 0
        context_parts << "Order lookups: #{summary[:lookup_count]}"
      end

      # Recent conversation (last 2 turns)
      recent_turns = state["turns"]&.last(2) || []
      unless recent_turns.empty?
        formatted_turns = recent_turns.map do |turn|
          "#{turn['role'] == 'user' ? 'User' : 'Assistant'}: #{turn['text']}"
        end.join("\n")
        context_parts << "Recent conversation:\n#{formatted_turns}"
      end

      context_parts.join("\n\n")
    end

    def handle_error(error, context)
      Rails.logger.error "[#{context}] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      respond(
        messages: text_message("Lo siento, tuve un problema consultando tu orden. ¿Puedes intentar de nuevo?"),
        state_patch: {
          "dialogue" => {
            "last_error" => error.message,
            "error_timestamp" => Time.now.utc.iso8601
          }
        }
      )
    end

    def system_instructions
      <<~INSTRUCTIONS
        You are a helpful order tracking specialist for Tony's Pizza that provides accurate order status information, shipping updates, and delivery estimates.

        Available tools:
        - OrderLookup: Search for orders by order ID with customer verification
        - ShippingStatus: Get real-time tracking information and delivery progress
        - DeliveryEstimate: Calculate estimated delivery times and ETAs

        Guidelines:
        - Always prioritize customer verification for security
        - Use OrderLookup when customers provide order numbers
        - For tracking requests, use ShippingStatus to get detailed delivery status
        - For ETA questions, use DeliveryEstimate to calculate arrival times
        - Be patient and helpful when customers can't find their order information
        - Clearly explain verification requirements (phone number needed)
        - Provide proactive updates and set realistic expectations
        - If an order is delayed, acknowledge and offer assistance

        Verification requirements:
        - Order lookups require customer verification for security
        - Accept last 4 digits of phone OR full phone number
        - If customer phone is already verified in session, verification not needed
        - Tools will handle verification automatically

        Response style:
        - Be friendly, professional, and reassuring
        - Use clear status indicators (📦 for orders, 🚚 for shipping, ⏰ for time)
        - Provide specific information (tracking numbers, times, locations)
        - Keep responses concise but informative
        - Offer next steps ("Would you like to track shipping?" or "Need help with anything else?")

        Order tracking workflow:
        1. Customer provides order number
        2. Verify identity with OrderLookup
        3. Show order status and details
        4. If shipped, offer tracking with ShippingStatus
        5. If in transit, provide ETA with DeliveryEstimate
        6. Confirm customer satisfaction

        Common scenarios:
        - "Where's my order?" → Use OrderLookup, then ShippingStatus if available
        - "When will it arrive?" → Use DeliveryEstimate with order context
        - "Track order XYZ" → Use ShippingStatus with tracking/order number
        - "Order delayed?" → Check status, provide realistic updates, offer support contact

        Important notes:
        - Never share order info without verification (security)
        - Always use tools to fetch real-time data (don't guess)
        - If tools return errors, explain clearly and offer alternatives
        - Tools return state_patch - updates apply automatically
        - Escalate to support agent for refunds, cancellations, or complaints
      INSTRUCTIONS
    end
  end
end
