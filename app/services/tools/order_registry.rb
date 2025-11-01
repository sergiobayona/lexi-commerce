# frozen_string_literal: true

# Tool registry for order-related tools
# Individual tools are defined in separate files in tools/order/ directory
#
# Provides ToolSpec entries for order-related functionality.
module Tools
  class OrderRegistry
    def self.specs
      [
        ToolSpec.new(
          id: :order_lookup,
          factory: lambda { |agent|
            Order::OrderLookup.new(
              agent.accessor_provider(State::Accessors::OrderAccessor),
              agent.state_provider
            )
          }
        ),
        ToolSpec.new(
          id: :shipping_status,
          factory: ->(agent) { Order::ShippingStatus.new(agent.accessor_provider(State::Accessors::OrderAccessor)) }
        ),
        ToolSpec.new(
          id: :delivery_estimate,
          factory: ->(agent) { Order::DeliveryEstimate.new(agent.accessor_provider(State::Accessors::OrderAccessor)) }
        )
      ]
    end
  end
end
