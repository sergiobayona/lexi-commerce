# frozen_string_literal: true

module Agents
  # Product agent handles product-specific questions (details, attributes, categories, availability, comparisons)
  # Uses RubyLLM with specialized product tools for intelligent product queries
  class ProductAgent < ToolEnabledAgent
    private

    def tool_specs(_state)
      Tools::ProductRegistry.specs
    end

    def build_context(state, **_)
      context_parts = []

      # Include recent turns for pronoun resolution ("the other one", "compare these")
      recent_turns = state["turns"]&.last(3) || []
      unless recent_turns.empty?
        formatted_turns = recent_turns.map do |turn|
          "#{turn['role'] == 'user' ? 'User' : 'Assistant'}: #{turn['text']}"
        end.join("\n")
        context_parts << "Recent conversation:\n#{formatted_turns}"
      end

      # Include products currently in focus
      product_focus = state.dig("slots", "product_focus") || []
      if product_focus.any?
        context_parts << "Products in focus: #{product_focus.join(', ')}"
      end

      context_parts.join("\n\n")
    end

    def build_state_patch(turn:, response_text:, **_)
      {
        "slots" => {
          "product_focus" => extract_product_ids(response_text),
          "last_product_query" => turn[:text]
        },
        "dialogue" => {
          "last_interaction" => Time.now.utc.iso8601
        }
      }
    end

    def extract_product_ids(response_text)
      # Extract product IDs from response (format: prod_XXX)
      response_text.scan(/prod_\d+/).uniq
    end

    def error_message
      "Lo siento, tuve un problema procesando tu consulta de productos. ¿Puedes intentar de nuevo?"
    end

    def system_instructions
      <<~INSTRUCTIONS
        You are a helpful product specialist for Tony's Pizza that provides accurate information about products, helps customers make informed decisions, and assists with product selection.

        Available tools:
        - ProductSearch: Search for products by name, category, or keyword
        - ProductDetails: Get detailed information about a specific product (ingredients, nutritional info, etc.)
        - ProductAvailability: Check if a product is in stock and available
        - ProductComparison: Compare multiple products side-by-side

        Guidelines:
        - Always use the appropriate tool to fetch accurate, up-to-date product information
        - Be friendly, professional, and helpful in your responses
        - When customers ask about products, use ProductSearch first to find relevant items
        - For specific product questions (ingredients, calories, etc.), use ProductDetails with the product ID
        - When customers ask "is it available", use ProductAvailability to check stock status
        - When customers want to compare products, use ProductComparison with multiple product IDs
        - If a customer refers to "the other one" or "these", check the conversation context for product IDs
        - Always verify information using tools rather than making assumptions
        - Format prices clearly in the local currency (Colombian pesos)
        - Highlight dietary information (vegetarian, vegan) and allergens when relevant
        - If a product is out of stock, suggest similar alternatives

        Response style:
        - Be concise but informative
        - Use emojis sparingly for visual appeal (🍕 for pizza, 🥤 for drinks, etc.)
        - Structure longer responses with bullet points or short paragraphs
        - Always end with a helpful follow-up question or suggestion
      INSTRUCTIONS
    end
  end
end
