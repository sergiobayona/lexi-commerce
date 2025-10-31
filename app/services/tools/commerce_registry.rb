# frozen_string_literal: true

# Tool registry for commerce-related tools
# Individual tools are defined in separate files in tools/commerce/ directory
#
# Usage:
#   tools = Tools::CommerceRegistry.all(cart_accessor: cart, state: state)
#   tools.each { |tool| agent.chat.with_tool(tool) }
#
# Note: Commerce tools require state accessors for cart management
module Tools
  class CommerceRegistry
    def self.all(cart_accessor_provider:, state_provider:)
      [
        Commerce::CartManager.new(cart_accessor_provider),
        Commerce::ProductCatalog.new,
        Commerce::CheckoutValidator.new(cart_accessor_provider, state_provider)
      ]
    end
  end
end
