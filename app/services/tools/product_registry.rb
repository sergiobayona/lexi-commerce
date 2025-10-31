# frozen_string_literal: true

# Tool registry for product-related tools
# Individual tools are defined in separate files in tools/product/ directory
#
# Usage:
#   tools = Tools::ProductRegistry.all
#   tools.each { |tool| agent.chat.with_tool(tool) }
module Tools
  class ProductRegistry
    def self.all
      [
        Product::ProductSearch,
        Product::ProductDetails,
        Product::ProductAvailability,
        Product::ProductComparison
      ]
    end
  end
end
