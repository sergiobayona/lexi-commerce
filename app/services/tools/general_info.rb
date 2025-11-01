# frozen_string_literal: true

# Tool registry for general information tools
# Individual tools are defined in separate files for better maintainability and autoloading
#
# Provides ToolSpec entries for general information tooling.
module Tools
  class GeneralInfo
    def self.specs
      [
        ToolSpec.new(id: :business_hours, factory: ->(_agent) { BusinessHours.new }),
        ToolSpec.new(id: :locations, factory: ->(_agent) { Locations.new }),
        ToolSpec.new(id: :general_faq, factory: ->(_agent) { GeneralFaq.new })
      ]
    end
  end
end
