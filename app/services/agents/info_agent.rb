# frozen_string_literal: true

module Agents
  # Info agent handles general information queries, business hours, FAQs, etc.
  class InfoAgent < BaseAgent
    attr_reader :chat

    def initialize(model: "gpt-4o-mini")
      super()
      @tools = Tools::GeneralInfo.all
      @chat = RubyLLM.chat(model: model)

      # Register all tools
      @tools.each { |tool| @chat.with_tool(tool) }

      # Set system instructions
      @chat.with_instructions(system_instructions)

      # Optional: Add tool call monitoring for debugging
      @chat.on_tool_call do |tool_call|
        Rails.logger.info "[InfoAgent] Tool invoked: #{tool_call.name} with params: #{tool_call.params}"
      end
    end

    def ask(question)
      Rails.logger.info "[InfoAgent] Processing question: #{question}"
      response = @chat.ask(question)
      Rails.logger.info "[InfoAgent] Response: #{response}"
      response
    rescue StandardError => e
      Rails.logger.error "[InfoAgent] Error processing question: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { error: "Unable to process your request. Please try again." }
    end

    private

    def system_instructions
      <<~INSTRUCTIONS
        You are a helpful assistant for Tony's Pizza that provides accurate and concise information about the business, its products, services, and policies.

        Available tools:
        - BusinessHours: Get business hours for specific days or check if currently open
        - Locations: Search for locations by name/city or find nearest location by coordinates
        - GeneralFaq: Search FAQ database by category or keyword

        Guidelines:
        - Always use the appropriate tool to fetch accurate, up-to-date information
        - Be friendly, professional, and concise in your responses
        - If a customer asks about hours, use the BusinessHours tool with the 'day' parameter if they mention a specific day
        - If a customer asks about locations, use the Locations tool with 'search' for city/name or 'latitude'/'longitude' for proximity
        - If a customer asks about policies, menu, dietary options, etc., use GeneralFaq with appropriate category or search query
        - Always verify information using tools rather than making assumptions
      INSTRUCTIONS
    end
  end
end
