# frozen_string_literal: true

module Tools
  # Declarative description of a tool entry that can be built by tool-enabled agents.
  # Encapsulates the factory used to instantiate the tool and whether the tool
  # should be wrapped for result collection.
  class ToolSpec
    attr_reader :id

    def initialize(id:, factory:, wrap: true)
      @id = id
      @factory = factory
      @wrap = wrap
    end

    # Build the tool instance for the provided agent context.
    # @param agent [Agents::ToolEnabledAgent] Agent requesting the tool
    # @return [RubyLLM::Tool] Tool instance ready for registration
    def build(agent)
      tool = @factory.call(agent)
      return tool unless wrap?

      agent.wrap_tool(tool)
    end

    private

    def wrap?
      @wrap
    end
  end
end
