# frozen_string_literal: true

# Tool registry for general information tools
# Individual tools are defined in separate files for better maintainability and autoloading
#
# Usage:
#   tools = Tools::GeneralInfo.all
#   tools.each { |tool| agent.register_tool(tool) }
module Tools
  class GeneralInfo
    def self.all
      [BusinessHours, Locations, GeneralFaq]
    end
  end
end
