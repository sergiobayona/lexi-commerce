# frozen_string_literal: true

module Tools
  module Product
    # ProductSearch tool for searching products by name, category, or attributes
    # This tool does not require state access - it queries product catalog data
    class ProductSearch < RubyLLM::Tool
      description "Search for products by name, category, or keyword. Returns list of matching products with basic details."

      param :query, type: :string, required: true,
            desc: "Search term (product name, category, or keyword)"
      param :category, type: :string, required: false,
            desc: "Optional category filter (e.g., 'food', 'drinks', 'desserts')"
      param :limit, type: :integer, required: false,
            desc: "Maximum number of results to return (default: 5)"

      def initialize
        # Hard-coded product catalog for MVP
        # TODO: Replace with actual product service/API integration
        @products = [
          {
            id: "prod_001",
            name: "Pizza Margherita",
            category: "food",
            price_cents: 12000,
            description: "Pizza clásica con tomate, mozzarella y albahaca fresca",
            available: true,
            tags: [ "vegetarian", "popular", "italian" ]
          },
          {
            id: "prod_002",
            name: "Pizza Pepperoni",
            category: "food",
            price_cents: 14000,
            description: "Pizza con abundante pepperoni y queso mozzarella",
            available: true,
            tags: [ "popular", "meat", "italian" ]
          },
          {
            id: "prod_003",
            name: "Coca-Cola 500ml",
            category: "drinks",
            price_cents: 3000,
            description: "Bebida gaseosa refrescante",
            available: true,
            tags: [ "beverage", "cold" ]
          },
          {
            id: "prod_004",
            name: "Tiramisu",
            category: "desserts",
            price_cents: 8000,
            description: "Postre italiano con café y mascarpone",
            available: true,
            tags: [ "dessert", "coffee", "italian" ]
          },
          {
            id: "prod_005",
            name: "Pizza Vegetariana",
            category: "food",
            price_cents: 13000,
            description: "Pizza con pimientos, champiñones, cebolla y aceitunas",
            available: true,
            tags: [ "vegetarian", "healthy" ]
          }
        ]
      end

      def execute(query:, category: nil, limit: 5)
        Rails.logger.info "[ProductSearch] Searching for: #{query}, category: #{category}, limit: #{limit}"

        # Filter by category if specified
        results = category ? @products.select { |p| p[:category] == category.downcase } : @products

        # Search by query term in name, description, or tags
        query_lower = query.downcase
        results = results.select do |product|
          product[:name].downcase.include?(query_lower) ||
            product[:description].downcase.include?(query_lower) ||
            product[:tags].any? { |tag| tag.include?(query_lower) }
        end

        # Limit results
        results = results.first(limit)

        if results.empty?
          return {
            found: false,
            message: "No se encontraron productos que coincidan con '#{query}'#{category ? " en la categoría '#{category}'" : ''}",
            suggestions: suggest_alternatives(query)
          }
        end

        {
          found: true,
          count: results.size,
          products: results.map do |p|
            {
              id: p[:id],
              name: p[:name],
              category: p[:category],
              price: "$#{p[:price_cents] / 100}",
              price_cents: p[:price_cents],
              description: p[:description],
              available: p[:available]
            }
          end
        }
      rescue StandardError => e
        Rails.logger.error "[ProductSearch] Error: #{e.message}"
        { error: "Error searching products: #{e.message}" }
      end

      private

      def suggest_alternatives(query)
        # Suggest popular items if search fails
        [ "Pizza Margherita", "Pizza Pepperoni", "Tiramisu" ]
      end
    end
  end
end
