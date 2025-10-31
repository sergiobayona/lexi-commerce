# frozen_string_literal: true

# Tool registry for support-related tools
# Individual tools are defined in separate files in tools/support/ directory
#
# Usage:
#   tools = Tools::SupportRegistry.all(case_accessor: case_accessor)
#   tools.each { |tool| agent.chat.with_tool(tool) }
#
# Note: Support tools include CaseManager which requires case state accessor
module Tools
  class SupportRegistry
    def self.all(case_accessor_provider:)
      [
        Support::RefundPolicy.new,
        Support::CaseManager.new(case_accessor_provider),
        Support::ContactSupport.new
      ]
    end
  end
end
