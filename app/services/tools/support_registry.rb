# frozen_string_literal: true

# Tool registry for support-related tools
# Individual tools are defined in separate files in tools/support/ directory
#
# Provides ToolSpec entries for support tooling. CaseManager requires a
# CaseAccessor which the agent supplies via accessor_provider.
module Tools
  class SupportRegistry
    def self.specs
      [
        ToolSpec.new(
          id: :refund_policy,
          factory: ->(_agent) { Support::RefundPolicy.new }
        ),
        ToolSpec.new(
          id: :case_manager,
          factory: ->(agent) { Support::CaseManager.new(agent.accessor_provider(State::Accessors::CaseAccessor)) }
        ),
        ToolSpec.new(
          id: :contact_support,
          factory: ->(_agent) { Support::ContactSupport.new }
        )
      ]
    end
  end
end
