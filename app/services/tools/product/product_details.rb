# frozen_string_literal: true

module Tools
  module Product
    # ProductDetails tool for getting detailed information about a specific product
    # This tool does not require state access - it queries product catalog data
    class ProductDetails < RubyLLM::Tool
      description "Get detailed information about a specific product including full description, ingredients, nutritional info, and specifications."

      param :product_id, type: :string, required: true,
            desc: "Product ID to get details for"

      def initialize
        # Hard-coded product details for MVP
        # TODO: Replace with actual product service/API integration
        @product_details = {
          "prod_001" => {
            id: "prod_001",
            name: "Pizza Margherita",
            category: "food",
            price_cents: 12000,
            description: "Pizza clásica italiana con salsa de tomate fresco, mozzarella de búfala y albahaca fresca. Horneada en horno de piedra a 450°C.",
            ingredients: [ "Masa artesanal", "Tomate San Marzano", "Mozzarella di Bufala", "Albahaca fresca", "Aceite de oliva extra virgen" ],
            size: "30cm (mediana)",
            servings: "2-3 personas",
            prep_time: "15-20 minutos",
            calories: "250 por porción",
            dietary: [ "vegetarian" ],
            allergens: [ "gluten", "lácteos" ],
            available: true,
            stock_status: "En stock",
            images: [ "https://example.com/margherita.jpg" ]
          },
          "prod_002" => {
            id: "prod_002",
            name: "Pizza Pepperoni",
            category: "food",
            price_cents: 14000,
            description: "Pizza americana con abundante pepperoni premium y queso mozzarella. Nuestra opción más popular.",
            ingredients: [ "Masa artesanal", "Salsa de tomate", "Mozzarella", "Pepperoni premium" ],
            size: "30cm (mediana)",
            servings: "2-3 personas",
            prep_time: "15-20 minutos",
            calories: "310 por porción",
            dietary: [],
            allergens: [ "gluten", "lácteos", "cerdo" ],
            available: true,
            stock_status: "En stock",
            images: [ "https://example.com/pepperoni.jpg" ]
          },
          "prod_003" => {
            id: "prod_003",
            name: "Coca-Cola 500ml",
            category: "drinks",
            price_cents: 3000,
            description: "Bebida gaseosa refrescante de 500ml. Servida fría.",
            ingredients: [ "Agua carbonatada", "Azúcar", "Caramelo", "Ácido fosfórico", "Cafeína" ],
            size: "500ml",
            servings: "1 persona",
            calories: "210 total",
            dietary: [ "vegan" ],
            allergens: [],
            available: true,
            stock_status: "En stock",
            images: [ "https://example.com/coca-cola.jpg" ]
          },
          "prod_004" => {
            id: "prod_004",
            name: "Tiramisu",
            category: "desserts",
            price_cents: 8000,
            description: "Postre italiano tradicional con capas de bizcochos empapados en café espresso, crema de mascarpone y cacao en polvo.",
            ingredients: [ "Bizcochos savoiardi", "Café espresso", "Mascarpone", "Huevos", "Azúcar", "Cacao" ],
            size: "Porción individual",
            servings: "1 persona",
            prep_time: "Listo para servir",
            calories: "450",
            dietary: [ "vegetarian" ],
            allergens: [ "gluten", "huevos", "lácteos" ],
            available: true,
            stock_status: "En stock",
            images: [ "https://example.com/tiramisu.jpg" ]
          },
          "prod_005" => {
            id: "prod_005",
            name: "Pizza Vegetariana",
            category: "food",
            price_cents: 13000,
            description: "Pizza saludable con variedad de vegetales frescos: pimientos rojos y verdes, champiñones, cebolla morada y aceitunas negras.",
            ingredients: [ "Masa artesanal", "Salsa de tomate", "Mozzarella", "Pimientos", "Champiñones", "Cebolla", "Aceitunas" ],
            size: "30cm (mediana)",
            servings: "2-3 personas",
            prep_time: "15-20 minutos",
            calories: "220 por porción",
            dietary: [ "vegetarian" ],
            allergens: [ "gluten", "lácteos" ],
            available: true,
            stock_status: "En stock",
            images: [ "https://example.com/vegetariana.jpg" ]
          }
        }
      end

      def execute(product_id:)
        Rails.logger.info "[ProductDetails] Fetching details for product: #{product_id}"

        product = @product_details[product_id]

        if product.nil?
          return {
            found: false,
            error: "Producto '#{product_id}' no encontrado",
            message: "No se encontró información para el producto especificado"
          }
        end

        {
          found: true,
          product: {
            id: product[:id],
            name: product[:name],
            category: product[:category],
            price: "$#{product[:price_cents] / 100}",
            price_cents: product[:price_cents],
            description: product[:description],
            ingredients: product[:ingredients],
            size: product[:size],
            servings: product[:servings],
            prep_time: product[:prep_time],
            calories: product[:calories],
            dietary_info: product[:dietary],
            allergens: product[:allergens],
            available: product[:available],
            stock_status: product[:stock_status]
          }
        }
      rescue StandardError => e
        Rails.logger.error "[ProductDetails] Error: #{e.message}"
        { error: "Error fetching product details: #{e.message}" }
      end
    end
  end
end
