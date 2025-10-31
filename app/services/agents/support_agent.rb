# frozen_string_literal: true

module Agents
  # Support agent handles customer service, complaints, refunds, order issues
  # Uses RubyLLM with specialized support tools and case state management
  class SupportAgent < BaseAgent
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
      Rails.logger.info "[SupportAgent] Handling intent '#{intent}' with question: #{question}"

      # Store state for accessor injection
      @state_holder[:state] = state

      # Register tools with state accessors
      register_tools_with_state

      # Build context from support case state and dialogue history
      context = build_context(state)

      # Use RubyLLM chat with tools to get the response
      full_question = context.empty? ? question : "#{context}\n\nUser question: #{question}"
      response = @chat.ask(full_question)

      # Extract text content from RubyLLM::Message object
      response_text = response.content.to_s

      # Build state patch
      state_patch = {
        "support" => {
          "last_interaction" => Time.now.utc.iso8601
        },
        "dialogue" => {
          "last_support_query" => question
        }
      }

      # Check if we should trigger human handoff based on conversation patterns
      if should_trigger_handoff?(state, response_text)
        Rails.logger.info "[SupportAgent] Triggering human handoff based on conversation analysis"
        # Don't modify state_patch here - let CaseManager handle it via tools
      end

      # Return structured AgentResponse
      respond(
        messages: text_message(response_text),
        state_patch: state_patch
      )
    rescue StandardError => e
      handle_error(e, "SupportAgent")
    end

    private

    def register_tools_with_state
      # Create accessor provider that will be called by tools
      case_accessor_provider = -> { State::Accessors::CaseAccessor.new(@state_holder[:state]) }

      # Get tools with injected accessors
      @tools = Tools::SupportRegistry.all(case_accessor_provider: case_accessor_provider)

      # Register all tools (clears previous registration)
      @tools.each { |tool| @chat.with_tool(tool) }

      # Set/update system instructions
      @chat.with_instructions(system_instructions)
    end

    def setup_tool_monitoring
      @chat.on_tool_call do |tool_call|
        Rails.logger.info "[SupportAgent] Tool invoked: #{tool_call.name} with arguments: #{tool_call.arguments}"
      end
    end

    def build_context(state)
      context_parts = []

      # Case context
      cases = State::Accessors::CaseAccessor.new(state)
      if cases.has_active_case?
        summary = cases.summary
        context_parts << "Active case: #{summary[:case_id]} (#{summary[:case_type]}, level #{summary[:escalation_level]})"
      end

      # Human handoff status
      if cases.human_handoff_requested?
        context_parts << "Human handoff requested"
      end

      # Recent complaint/negative sentiment analysis
      recent_turns = state["turns"]&.last(5) || []
      negative_turns = recent_turns.select { |turn| turn["role"] == "user" && contains_negative_sentiment?(turn["text"]) }
      if negative_turns.size >= 2
        context_parts << "Customer frustration detected (#{negative_turns.size} negative messages)"
      end

      # Recent conversation (last 3 turns)
      unless recent_turns.empty?
        formatted_turns = recent_turns.last(3).map do |turn|
          "#{turn['role'] == 'user' ? 'User' : 'Assistant'}: #{turn['text']}"
        end.join("\n")
        context_parts << "Recent conversation:\n#{formatted_turns}"
      end

      context_parts.join("\n\n")
    end

    def contains_negative_sentiment?(text)
      # Simple keyword-based sentiment detection
      # TODO: Replace with proper sentiment analysis
      negative_keywords = %w[
        malo terrible horrible frustrado enojado molesto
        problema error falla nunca siempre pésimo
        bad terrible horrible frustrated angry upset
        problem error issue never always awful
      ]

      text_lower = text.downcase
      negative_keywords.any? { |keyword| text_lower.include?(keyword) }
    end

    def should_trigger_handoff?(state, response)
      # Check if customer has shown persistent frustration
      cases = State::Accessors::CaseAccessor.new(state)

      # Already requested handoff
      return false if cases.human_handoff_requested?

      # Check escalation level
      if cases.has_active_case?
        active_case = cases.get_active_case
        return true if active_case[:escalation_level] >= 2
      end

      # Check for repeated complaints
      recent_turns = state["turns"]&.last(10) || []
      negative_count = recent_turns.count { |turn| turn["role"] == "user" && contains_negative_sentiment?(turn["text"]) }

      negative_count >= 3
    end

    def handle_error(error, context)
      Rails.logger.error "[#{context}] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      respond(
        messages: text_message("Lo siento, tuve un problema procesando tu solicitud de soporte. ¿Puedes intentar de nuevo o prefieres hablar con un agente humano?"),
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
        You are a compassionate and professional customer support agent for Tony's Pizza that helps resolve customer issues, handles complaints, processes refunds, and provides excellent service recovery.

        Available tools:
        - RefundPolicy: Get detailed refund, return, exchange, and cancellation policy information
        - CaseManager: Create, update, close, escalate support cases, or request human handoff
        - ContactSupport: Provide contact information for human support team

        Guidelines:
        - Always be empathetic, patient, and understanding with frustrated customers
        - Listen carefully to customer concerns before offering solutions
        - Use RefundPolicy to provide accurate policy information
        - Create cases with CaseManager for tracking and follow-up
        - Escalate complex issues or persistent problems using CaseManager action='escalate'
        - Request human handoff when:
          * Customer explicitly asks to speak with a person
          * Issue requires authority beyond your scope
          * Customer shows persistent frustration after multiple attempts
          * Escalation level reaches 2 or higher
        - Be proactive in offering compensation or solutions within policy guidelines
        - Always confirm customer satisfaction before closing cases
        - Document all interactions in case notes

        Response style:
        - Be warm, empathetic, and professional
        - Acknowledge customer emotions ("I understand this is frustrating")
        - Apologize sincerely when appropriate
        - Provide clear solutions with specific next steps
        - Set realistic expectations for resolution timelines
        - Use emojis sparingly and appropriately (😔 for empathy, ✅ for solutions)
        - Keep responses concise but thorough

        Support workflow:
        1. Acknowledge issue and empathize
        2. Gather necessary details
        3. Create case with CaseManager if needed
        4. Check policies with RefundPolicy
        5. Offer solution within policy guidelines
        6. Confirm customer satisfaction
        7. Close case or escalate if needed

        Escalation triggers:
        - Customer frustrated after 2+ attempts to resolve
        - Issue requires manager approval
        - Policy exception needed
        - Complex technical or billing issues
        - Legal or compliance concerns

        Important notes:
        - Never promise what you can't deliver
        - Always follow company policies (use RefundPolicy tool)
        - Document everything in case notes
        - Prioritize customer satisfaction and retention
        - When in doubt, escalate or request human handoff
        - Tools return state_patch - updates apply automatically
      INSTRUCTIONS
    end
  end
end
