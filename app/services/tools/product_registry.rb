# frozen_string_literal: true

# Tool registry for product-related tools
# Individual tools are defined in separate files in tools/product/ directory
#
# Provides ToolSpec entries for product catalogue tooling.
module Tools
  class ProductRegistry
    def self.specs
      [
        ToolSpec.new(id: :product_search, factory: ->(_agent) { Product::ProductSearch.new }),
        ToolSpec.new(id: :product_details, factory: ->(_agent) { Product::ProductDetails.new }),
        ToolSpec.new(id: :product_availability, factory: ->(_agent) { Product::ProductAvailability.new }),
        ToolSpec.new(id: :product_comparison, factory: ->(_agent) { Product::ProductComparison.new })
      ]
    end
  end
end
