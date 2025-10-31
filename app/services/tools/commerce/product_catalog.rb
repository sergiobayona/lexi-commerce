# frozen_string_literal: true

module Tools
  module Commerce
    # ProductCatalog tool for browsing product categories and featured items
    # This tool does not require state access - it provides catalog navigation
    class ProductCatalog < RubyLLM::Tool
      description "Browse product catalog by categories, view featured items, or get category listings. Helps customers discover products."

      param :action, type: :string, required: true,
            desc: "Action: 'list_categories', 'browse_category', 'featured_items'"
      param :category, type: :string, required: false,
            desc: "Category name for browse_category action (e.g., 'food', 'drinks', 'desserts')"

      def execute(action:, category: nil)
        Rails.logger.info "[ProductCatalog] Action: #{action}, Category: #{category}"

        case action.downcase
        when "list_categories"
          list_categories
        when "browse_category"
          browse_category(category)
        when "featured_items"
          featured_items
        else
          { error: "Invalid action '#{action}'. Valid actions: list_categories, browse_category, featured_items" }
        end
      rescue StandardError => e
        Rails.logger.error "[ProductCatalog] Error: #{e.message}"
        { error: "Catalog operation failed: #{e.message}" }
      end

      private

      def list_categories
        {
          action: "list_categories",
          categories: [
            {
              id: "food",
              name: "🍕 Comida",
              description: "Pizzas y platos principales",
              item_count: 3
            },
            {
              id: "drinks",
              name: "🥤 Bebidas",
              description: "Refrescos y bebidas frías",
              item_count: 1
            },
            {
              id: "desserts",
              name: "🍰 Postres",
              description: "Dulces y delicias",
              item_count: 1
            }
          ],
          message: "Tenemos 3 categorías disponibles"
        }
      end

      def browse_category(category_name)
        return { error: "category parameter is required for browse_category action" } unless category_name

        category_products = {
          "food" => [
            { id: "prod_001", name: "Pizza Margherita", price: "$12,000", description: "Pizza clásica con tomate y mozzarella" },
            { id: "prod_002", name: "Pizza Pepperoni", price: "$14,000", description: "Pizza con abundante pepperoni" },
            { id: "prod_005", name: "Pizza Vegetariana", price: "$13,000", description: "Pizza con vegetales frescos" }
          ],
          "drinks" => [
            { id: "prod_003", name: "Coca-Cola 500ml", price: "$3,000", description: "Bebida refrescante" }
          ],
          "desserts" => [
            { id: "prod_004", name: "Tiramisu", price: "$8,000", description: "Postre italiano con café" }
          ]
        }

        category_key = category_name.downcase
        products = category_products[category_key]

        if products.nil?
          return {
            found: false,
            error: "Category '#{category_name}' not found",
            available_categories: category_products.keys
          }
        end

        {
          action: "browse_category",
          category: category_name,
          products: products,
          count: products.size,
          message: "Categoría #{category_name}: #{products.size} #{products.size == 1 ? 'producto' : 'productos'} disponibles"
        }
      end

      def featured_items
        {
          action: "featured_items",
          featured: [
            {
              id: "prod_002",
              name: "Pizza Pepperoni",
              price: "$14,000",
              description: "Nuestra pizza más popular",
              badge: "⭐ Más vendida"
            },
            {
              id: "prod_001",
              name: "Pizza Margherita",
              price: "$12,000",
              description: "Pizza clásica italiana",
              badge: "🌿 Vegetariana"
            },
            {
              id: "prod_004",
              name: "Tiramisu",
              price: "$8,000",
              description: "Postre italiano tradicional",
              badge: "🍰 Especialidad"
            }
          ],
          message: "✨ Nuestros productos destacados"
        }
      end
    end
  end
end
