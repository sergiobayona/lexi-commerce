# frozen_string_literal: true

module Agents
  # Commerce agent handles shopping cart, orders, product browsing, checkout
  # Uses RubyLLM with specialized commerce tools and state accessors for cart management
  class CommerceAgent < BaseAgent
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
      Rails.logger.info "[CommerceAgent] Handling intent '#{intent}' with question: #{question}"

      # Store state for accessor injection
      @state_holder[:state] = state

      # Register tools with state accessors
      register_tools_with_state

      # Build context from cart and commerce state
      context = build_context(state)

      # Use RubyLLM chat with tools to get the response
      full_question = context.empty? ? question : "#{context}\n\nUser question: #{question}"
      response = @chat.ask(full_question)

      # Extract state patches from tool responses if present
      # Tools return state_patch in their responses, we need to merge them
      state_patch = extract_state_patches_from_response(response)

      # Add standard commerce state updates
      state_patch.deep_merge!({
        "commerce" => {
          "last_interaction" => Time.now.utc.iso8601
        },
        "dialogue" => {
          "last_commerce_query" => question
        }
      })

      # Return structured AgentResponse
      respond(
        messages: text_message(response),
        state_patch: state_patch
      )
    rescue StandardError => e
      handle_error(e, "CommerceAgent")
    end

    private

    def register_tools_with_state
      # Create accessor providers that will be called by tools
      cart_accessor_provider = -> { State::Accessors::CartAccessor.new(@state_holder[:state]) }
      state_provider = -> { @state_holder[:state] }

      # Get tools with injected accessors
      @tools = Tools::CommerceRegistry.all(
        cart_accessor_provider: cart_accessor_provider,
        state_provider: state_provider
      )

      # Register all tools (clears previous registration)
      @tools.each { |tool| @chat.with_tool(tool) }

      # Set/update system instructions
      @chat.with_instructions(system_instructions)
    end

    def setup_tool_monitoring
      @chat.on_tool_call do |tool_call|
        Rails.logger.info "[CommerceAgent] Tool invoked: #{tool_call.name} with arguments: #{tool_call.arguments}"
      end
    end

    def build_context(state)
      context_parts = []

      # Cart context
      cart = State::Accessors::CartAccessor.new(state)
      unless cart.empty?
        summary = cart.summary
        context_parts << "Cart: #{summary[:item_count]} items, subtotal #{summary[:subtotal]}"
      end

      # Commerce state
      commerce_state = state.dig("commerce", "state")
      if commerce_state
        context_parts << "Commerce state: #{commerce_state}"
      end

      # Recent conversation (last 2 turns for context)
      recent_turns = state["turns"]&.last(2) || []
      unless recent_turns.empty?
        formatted_turns = recent_turns.map do |turn|
          "#{turn['role'] == 'user' ? 'User' : 'Assistant'}: #{turn['text']}"
        end.join("\n")
        context_parts << "Recent conversation:\n#{formatted_turns}"
      end

      context_parts.join("\n\n")
    end

    def extract_state_patches_from_response(response)
      # RubyLLM tools can return state_patch in their responses
      # This is a placeholder for now - in a more sophisticated setup,
      # we'd parse tool results to extract state patches
      # For now, tools handle state updates, so return empty patch
      {}
    end

    def handle_error(error, context)
      Rails.logger.error "[#{context}] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      respond(
        messages: text_message("Lo siento, tuve un problema procesando tu solicitud de compra. ¿Puedes intentar de nuevo?"),
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
        You are a helpful shopping assistant for Tony's Pizza that helps customers browse products, manage their cart, and complete purchases.

        Available tools:
        - CartManager: View, add, remove, update, or clear cart items
        - ProductCatalog: Browse categories, view featured items, explore product listings
        - CheckoutValidator: Validate if customer can proceed to checkout

        Guidelines:
        - Always use the appropriate tool to perform cart operations and catalog browsing
        - Be friendly, helpful, and guide customers through the shopping process
        - When customers want to add items, use CartManager with action='add'
        - When customers want to see their cart, use CartManager with action='view'
        - When customers want to browse, use ProductCatalog to show categories or featured items
        - Before checkout, use CheckoutValidator to ensure all requirements are met
        - Format prices clearly in Colombian pesos (e.g., $12,000)
        - Confirm cart operations with clear feedback ("✅ Item added", "Cart total: $XX,XXX")
        - If cart is empty and customer wants to checkout, guide them to add products first
        - Suggest related products or upsells when appropriate
        - For product details (ingredients, allergens), suggest switching to product agent

        Response style:
        - Be conversational and helpful
        - Use emojis sparingly (🛒 for cart, ✅ for success, ⚠️ for warnings)
        - Provide clear next steps (e.g., "Ready to checkout?" or "Want to add more items?")
        - Keep responses concise but informative
        - Always confirm actions taken (items added/removed, quantities updated)

        Cart operations workflow:
        1. Browse products → Use ProductCatalog
        2. Add to cart → Use CartManager action='add'
        3. Review cart → Use CartManager action='view'
        4. Validate checkout → Use CheckoutValidator
        5. Proceed to payment → Confirm and guide next steps

        Important notes:
        - Tools return state_patch - these updates will be applied automatically
        - Always check tool responses for errors before responding to customer
        - If a tool returns an error, explain the issue and suggest alternatives
        - Minimum order amount is $10,000 - inform customers if below threshold
      INSTRUCTIONS
    end
  end
end
