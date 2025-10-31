# frozen_string_literal: true

module Agents
  # Product agent handles product-specific questions (details, attributes, categories, availability, comparisons)
  # Uses RubyLLM with specialized product tools for intelligent product queries
  class ProductAgent < BaseAgent
    attr_reader :chat

    def initialize(model: "gpt-4o-mini")
      @model = model
      @tools = Tools::ProductRegistry.all
      @chat = RubyLLM.chat(model: @model)

      # Register all tools
      @tools.each { |tool| @chat.with_tool(tool) }

      # Set system instructions
      @chat.with_instructions(system_instructions)

      # Add tool call monitoring for debugging
      @chat.on_tool_call do |tool_call|
        Rails.logger.info "[ProductAgent] Tool invoked: #{tool_call.name} with arguments: #{tool_call.arguments}"
      end
    end

    # Implement required BaseAgent interface
    def handle(turn:, state:, intent:)
      question = turn[:text]
      Rails.logger.info "[ProductAgent] Handling intent '#{intent}' with question: #{question}"

      # Build context from recent conversation and product focus
      context = build_context(state)

      # Use RubyLLM chat with tools to get the response
      full_question = context.empty? ? question : "#{context}\n\nUser question: #{question}"
      response = @chat.ask(full_question)

      # Extract text content from RubyLLM::Message object
      response_text = response.content.to_s

      # Extract product IDs mentioned in conversation for context tracking
      product_ids = extract_product_ids(response_text)

      # Return structured AgentResponse
      respond(
        messages: text_message(response_text),
        state_patch: {
          "slots" => {
            "product_focus" => product_ids,
            "last_product_query" => question
          },
          "dialogue" => {
            "last_interaction" => Time.now.utc.iso8601
          }
        }
      )
    rescue StandardError => e
      handle_error(e, "ProductAgent")
    end

    private

    def build_context(state)
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

    def extract_product_ids(response_text)
      # Extract product IDs from response (format: prod_XXX)
      response_text.scan(/prod_\d+/).uniq
    end

    def handle_error(error, context)
      Rails.logger.error "[#{context}] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      respond(
        messages: text_message("Lo siento, tuve un problema procesando tu consulta de productos. ¿Puedes intentar de nuevo?"),
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
