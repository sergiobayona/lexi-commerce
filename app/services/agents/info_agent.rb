# frozen_string_literal: true

module Agents
  # Info agent handles general information queries, business hours, FAQs, etc.
  class InfoAgent < BaseAgent
    def initialize
      @tools = Tools::GeneralInfo.all
      chat = RubyLLM.chat

      # Set the initial instruction
      chat.with_instructions(system_prompt)

      response = chat.ask "What is a variable?"
    end

    def system_instructions
      <<~INSTRUCTIONS
        You are a helpful assistant that provides accurate and concise information about the business, its products, services, and policies. Use the available tools to fetch up-to-date information when needed. Always aim to resolve the customer's inquiry in a friendly and professional manner.
      INSTRUCTIONS
    end
  end
end
