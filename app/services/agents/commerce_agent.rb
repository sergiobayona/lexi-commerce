# frozen_string_literal: true

module Agents
  # Commerce agent handles shopping cart, orders, product browsing, checkout
  # Uses RubyLLM with specialized commerce tools and state accessors for cart management
  class CommerceAgent < ToolEnabledAgent
    private

    def tool_specs(_state)
      Tools::CommerceRegistry.specs
    end

    def build_context(state, **_)
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

    def build_state_patch(turn:, **_)
      {
        "commerce" => {
          "last_interaction" => Time.now.utc.iso8601
        },
        "dialogue" => {
          "last_commerce_query" => turn[:text]
        }
      }
    end

    def error_message
      "Lo siento, tuve un problema procesando tu solicitud de compra. ¿Puedes intentar de nuevo?"
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
