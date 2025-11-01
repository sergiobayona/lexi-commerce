# frozen_string_literal: true

module Agents
  # Base class for agents that rely on RubyLLM tools. Centralises chat lifecycle,
  # tool registration, result collection, and turn orchestration while allowing
  # concrete agents to focus on domain-specific context and state updates.
  class ToolEnabledAgent < BaseAgent
    attr_reader :chat

    def initialize(model: "gpt-4o-mini")
      super()
      @model = model
      @state_holder = { state: nil }
      @tool_results = []
      @chat = RubyLLM.chat(model: model)
      setup_chat_callbacks
    end

    def handle(turn:, state:, intent:)
      prepare_for_turn(state)

      question = turn[:text]
      Rails.logger.info "[#{agent_log_prefix}] Handling intent '#{intent}' with question: #{question}"

      context = build_context(state, intent: intent)
      response = ask_with_context(question, context)
      response_text = extract_text(response)

      tool_patch = tool_state_patch
      agent_patch = build_state_patch(
        turn: turn,
        state: state,
        intent: intent,
        response_text: response_text,
        tool_patch: tool_patch
      )
      merged_patch = merge_patches(tool_patch, agent_patch)

      messages = build_messages(response_text, response: response)

      final_patch, baton = post_process(
        turn: turn,
        state: state,
        intent: intent,
        response_text: response_text,
        state_patch: merged_patch,
        tool_patch: tool_patch
      )

      respond(
        messages: messages,
        state_patch: final_patch,
        baton: baton
      )
    rescue StandardError => e
      handle_error(e, agent_log_prefix, custom_message: error_message)
    ensure
      after_turn_cleanup
    end

    protected

    # Concrete agents must provide ToolSpec objects for the current state.
    # @param state [Hash] Session state
    # @return [Array<Tools::ToolSpec>]
    def tool_specs(_state)
      raise NotImplementedError, "#{self.class.name} must implement #tool_specs"
    end

    def system_instructions
      raise NotImplementedError, "#{self.class.name} must implement #system_instructions"
    end

    # Optional hook for providing additional context to the LLM.
    def build_context(_state, intent:)
      "" # Subclasses override to provide richer context
    end

    # Optional hook for domain-specific state updates. Receives tool patches so
    # agents can base their own updates on tool outcomes.
    def build_state_patch(turn:, state:, intent:, response_text:, tool_patch:)
      {}
    end

    # Override to customise outgoing WhatsApp messages.
    def build_messages(response_text, response:)
      text_message(response_text)
    end

    # Hook invoked after patches have been merged but before responding. Allows
    # subclasses to modify the state patch or request baton handoffs.
    def post_process(turn:, state:, intent:, response_text:, state_patch:, tool_patch:)
      [state_patch, nil]
    end

    # Customise error copy while retaining shared logging behaviour.
    def error_message
      "Lo siento, tuve un problema procesando tu solicitud. ¿Puedes intentar de nuevo?"
    end

    # Provides a provider that instantiates the accessor with the latest state.
    def accessor_provider(accessor_class)
      -> { accessor_class.new(@state_holder[:state]) }
    end

    # Provides a lambda returning the most recent state reference.
    def state_provider
      -> { @state_holder[:state] }
    end

    # Wrap tool instances when RubyLLM doesn't support on_tool_result callbacks.
    def wrap_tool(tool)
      return tool if @tool_result_callback_supported

      ToolProxy.new(tool, method(:collect_tool_result))
    end

    # Allows subclasses/tests to reset chat tools after registration.
    def replace_existing_tools
      chat.with_tools(replace: true) if chat.respond_to?(:with_tools)
    end

    def agent_log_prefix
      self.class.name.demodulize
    end

    private

    def prepare_for_turn(state)
      @state_holder[:state] = state
      @tool_results.clear
      register_tools_for_state(state)
    end

    def register_tools_for_state(state)
      specs = Array(tool_specs(state))
      replace_existing_tools

      specs.each do |spec|
        tool = spec.build(self)
        chat.with_tool(tool)
      end

      chat.with_instructions(system_instructions)
    end

    def setup_chat_callbacks
      chat.on_tool_call do |tool_call|
        Rails.logger.info "[#{agent_log_prefix}] Tool invoked: #{tool_call.name} with arguments: #{tool_call.arguments}"
      end

      @tool_result_callback_supported = chat.respond_to?(:on_tool_result)
      return unless @tool_result_callback_supported

      chat.on_tool_result do |result|
        collect_tool_result(result)
      end
    end

    def collect_tool_result(result)
      Rails.logger.info "[#{agent_log_prefix}] Tool result: #{result.inspect}"
      @tool_results << result
    end

    def ask_with_context(question, context)
      prompt = context.to_s.strip.empty? ? question : "#{context}\n\nUser question: #{question}"
      chat.ask(prompt)
    end

    def extract_text(response)
      response.respond_to?(:content) ? response.content.to_s : response.to_s
    end

    def tool_state_patch
      @tool_results.each_with_object({}) do |result, memo|
        next unless result.is_a?(Hash)

        patch = result[:state_patch] || result["state_patch"]
        memo.deep_merge!(patch) if patch.is_a?(Hash)
      end
    end

    def merge_patches(tool_patch, agent_patch)
      base_patch = tool_patch.present? ? tool_patch.deep_dup : {}
      agent_patch.present? ? base_patch.deep_merge(agent_patch) : base_patch
    end

    def after_turn_cleanup
      @state_holder[:state] = nil
    end

    # Wrapper that forwards behaviour to the original tool while capturing
    # results for state patch aggregation when RubyLLM lacks result callbacks.
    class ToolProxy
      def initialize(tool, collector)
        @tool = tool
        @collector = collector
      end

      def execute(**kwargs)
        result = @tool.execute(**kwargs)
        @collector.call(result)
        result
      end

      def method_missing(method_name, *args, &block)
        @tool.public_send(method_name, *args, &block)
      end

      def respond_to_missing?(method_name, include_private = false)
        @tool.respond_to?(method_name, include_private)
      end
    end
  end
end
