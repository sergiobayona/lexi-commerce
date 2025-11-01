# frozen_string_literal: true

# Tool registry for commerce-related tools
# Individual tools are defined in separate files in tools/commerce/ directory
#
# Usage:
#   specs = Tools::CommerceRegistry.specs
#   specs.each { |spec| agent.register(spec) }
module Tools
  class CommerceRegistry
    def self.specs
      [
        ToolSpec.new(
          id: :cart_manager,
          factory: ->(agent) { Commerce::CartManager.new(agent.accessor_provider(State::Accessors::CartAccessor)) }
        ),
        ToolSpec.new(
          id: :product_catalog,
          factory: ->(_agent) { Commerce::ProductCatalog.new }
        ),
        ToolSpec.new(
          id: :checkout_validator,
          factory: lambda { |agent|
            Commerce::CheckoutValidator.new(
              agent.accessor_provider(State::Accessors::CartAccessor),
              agent.state_provider
            )
          }
        )
      ]
    end
  end
end
