# frozen_string_literal: true

module Tools
  module Product
    # ProductComparison tool for comparing multiple products side-by-side
    # This tool does not require state access - it queries product catalog data
    class ProductComparison < RubyLLM::Tool
      description "Compare multiple products side-by-side. Shows differences in price, features, ingredients, and other attributes."

      param :product_ids, type: :array, required: true,
            desc: "Array of product IDs to compare (2-4 products recommended)",
            items: { type: :string }

      def initialize
        # Hard-coded product data for MVP (same as ProductDetails)
        # TODO: Replace with actual product service/API integration
        @products = {
          "prod_001" => {
            id: "prod_001",
            name: "Pizza Margherita",
            category: "food",
            price_cents: 12000,
            size: "30cm",
            calories: "250/porción",
            dietary: ["vegetarian"],
            allergens: ["gluten", "lácteos"],
            prep_time: "15-20 min"
          },
          "prod_002" => {
            id: "prod_002",
            name: "Pizza Pepperoni",
            category: "food",
            price_cents: 14000,
            size: "30cm",
            calories: "310/porción",
            dietary: [],
            allergens: ["gluten", "lácteos", "cerdo"],
            prep_time: "15-20 min"
          },
          "prod_003" => {
            id: "prod_003",
            name: "Coca-Cola 500ml",
            category: "drinks",
            price_cents: 3000,
            size: "500ml",
            calories: "210 total",
            dietary: ["vegan"],
            allergens: [],
            prep_time: "Inmediato"
          },
          "prod_004" => {
            id: "prod_004",
            name: "Tiramisu",
            category: "desserts",
            price_cents: 8000,
            size: "Individual",
            calories: "450",
            dietary: ["vegetarian"],
            allergens: ["gluten", "huevos", "lácteos"],
            prep_time: "Inmediato"
          },
          "prod_005" => {
            id: "prod_005",
            name: "Pizza Vegetariana",
            category: "food",
            price_cents: 13000,
            size: "30cm",
            calories: "220/porción",
            dietary: ["vegetarian"],
            allergens: ["gluten", "lácteos"],
            prep_time: "15-20 min"
          }
        }
      end

      def execute(product_ids:)
        Rails.logger.info "[ProductComparison] Comparing products: #{product_ids.join(', ')}"

        # Validate input
        if product_ids.empty?
          return { error: "Debe proporcionar al menos un producto para comparar" }
        end

        if product_ids.size > 4
          return {
            error: "Máximo 4 productos por comparación",
            message: "Por favor, seleccione hasta 4 productos para una comparación más clara"
          }
        end

        # Fetch products
        found_products = []
        missing_products = []

        product_ids.each do |pid|
          if @products.key?(pid)
            found_products << @products[pid]
          else
            missing_products << pid
          end
        end

        if found_products.empty?
          return {
            error: "No se encontraron productos válidos para comparar",
            missing_ids: missing_products
          }
        end

        # Build comparison
        comparison = {
          count: found_products.size,
          products: found_products.map { |p| build_comparison_row(p) },
          summary: build_comparison_summary(found_products)
        }

        # Add warning if some products were not found
        if missing_products.any?
          comparison[:warning] = "Algunos productos no fueron encontrados: #{missing_products.join(', ')}"
        end

        comparison
      rescue StandardError => e
        Rails.logger.error "[ProductComparison] Error: #{e.message}"
        { error: "Error comparing products: #{e.message}" }
      end

      private

      def build_comparison_row(product)
        {
          id: product[:id],
          name: product[:name],
          category: product[:category],
          price: "$#{product[:price_cents] / 100}",
          price_cents: product[:price_cents],
          size: product[:size],
          calories: product[:calories],
          dietary: product[:dietary],
          allergens: product[:allergens],
          prep_time: product[:prep_time]
        }
      end

      def build_comparison_summary(products)
        price_range = products.map { |p| p[:price_cents] }
        cheapest = products.min_by { |p| p[:price_cents] }
        most_expensive = products.max_by { |p| p[:price_cents] }

        summary = {
          price_range: "$#{price_range.min / 100} - $#{price_range.max / 100}",
          cheapest_option: {
            name: cheapest[:name],
            price: "$#{cheapest[:price_cents] / 100}"
          },
          most_expensive_option: {
            name: most_expensive[:name],
            price: "$#{most_expensive[:price_cents] / 100}"
          }
        }

        # Add dietary summary
        all_vegetarian = products.all? { |p| p[:dietary].include?("vegetarian") }
        all_vegan = products.all? { |p| p[:dietary].include?("vegan") }

        if all_vegan
          summary[:dietary_note] = "Todas las opciones son veganas"
        elsif all_vegetarian
          summary[:dietary_note] = "Todas las opciones son vegetarianas"
        end

        # Common allergens
        all_allergens = products.flat_map { |p| p[:allergens] }.uniq
        if all_allergens.any?
          summary[:common_allergens] = all_allergens
        end

        summary
      end
    end
  end
end
