# frozen_string_literal: true

# Tool registry for order-related tools
# Individual tools are defined in separate files in tools/order/ directory
#
# Usage:
#   tools = Tools::OrderRegistry.all(order_accessor: order_accessor, state: state)
#   tools.each { |tool| agent.chat.with_tool(tool) }
#
# Note: Order tools require order state accessor for verification and tracking
module Tools
  class OrderRegistry
    def self.all(order_accessor_provider:, state_provider:)
      [
        Order::OrderLookup.new(order_accessor_provider, state_provider),
        Order::ShippingStatus.new(order_accessor_provider),
        Order::DeliveryEstimate.new(order_accessor_provider)
      ]
    end
  end
end
