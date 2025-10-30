# frozen_string_literal: true

module Agents
  # Base agent interface that all lane-specific agents must implement
  # Defines the contract for agent behavior and response structure
  class BaseAgent
    # Lightweight baton passed between agents through the orchestrator loop
    Baton = Data.define(:target, :payload)

    # AgentResponse data structure
    # messages: Array of message hashes to send to user
    # state_patch: Hash of updates to apply to session state (deep merged)
    # baton: Optional Baton directing orchestration to another agent
    AgentResponse = Data.define(:messages, :state_patch, :baton)

    # Main handler method that all agents must implement
    # @param turn [Hash] The incoming turn data
    #   - tenant_id [String] Tenant identifier
    #   - wa_id [String] WhatsApp user ID
    #   - message_id [String] Unique message identifier
    #   - text [String] User's message text
    #   - payload [String, nil] Interactive button/list payload
    #   - timestamp [String] ISO8601 timestamp
    #
    # @param state [Hash] Current session state (Contract-shaped)
    #   - meta [Hash] Session metadata
    #   - dialogue [Hash] Conversation history
    #   - slots [Hash] Extracted entities
    #   - commerce [Hash] Shopping cart and order state
    #   - support [Hash] Support case tracking
    #   - version [Integer] State version for optimistic locking
    #
    # @param intent [String] Router-determined intent (e.g., "start_order", "business_hours")
    #
    # @return [AgentResponse] Response with messages, state updates, and optional handoff
    def handle(turn:, state:, intent:)
      raise NotImplementedError, "Agents must implement #handle"
    end

    protected

    # Helper to create a text message
    def text_message(body)
      {
        type: "text",
        text: { body: body }
      }
    end

    # Helper to create a button message
    def button_message(body:, buttons:)
      {
        type: "interactive",
        interactive: {
          type: "button",
          body: { text: body },
          action: {
            buttons: buttons.map.with_index do |btn, idx|
              {
                type: "reply",
                reply: {
                  id: btn[:id] || "btn_#{idx}",
                  title: btn[:title]
                }
              }
            end
          }
        }
      }
    end

    # Helper to create a list message
    def list_message(body:, button_text:, sections:)
      {
        type: "interactive",
        interactive: {
          type: "list",
          body: { text: body },
          action: {
            button: button_text,
            sections: sections.map do |section|
              {
                title: section[:title],
                rows: section[:rows].map do |row|
                  {
                    id: row[:id],
                    title: row[:title],
                    description: row[:description]
                  }
                end
              }
            end
          }
        }
      }
    end

    # Helper to request baton handoff to another lane
    def baton_to(lane:, payload: {})
      Baton.new(lane, payload)
    end

    # Helper to build standard response
    def respond(messages:, state_patch: {}, baton: nil)
      AgentResponse.new(
        messages: Array(messages),
        state_patch: state_patch,
        baton: baton
      )
    end
  end
end
