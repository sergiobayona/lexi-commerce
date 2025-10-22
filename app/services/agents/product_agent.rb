# frozen_string_literal: true

module Agents
  # Product agent handles product-specific questions (details, attributes, categories, availability, comparisons)
  class ProductAgent < BaseAgent
    def handle(turn:, state:, intent:)
      case intent
      when "product_details"
        handle_product_details(turn, state)
      when "product_comparison"
        handle_product_comparison(turn, state)
      when "product_availability"
        handle_product_availability(turn, state)
      when "product_categories"
        handle_product_categories(turn, state)
      else
        handle_product_default(turn, state)
      end
    end

    private

    def handle_product_details(turn, state)
      respond(
        messages: text_message(
          "📋 ¿Sobre qué producto te gustaría saber más?\n\n" \
          "Puedo contarte sobre ingredientes, precio, tamaño, etc."
        ),
        state_patch: {
          "slots" => {
            "awaiting_product_name" => true
          }
        }
      )
    end

    def handle_product_comparison(turn, state)
      respond(
        messages: text_message(
          "🔍 ¿Qué productos te gustaría comparar?\n\n" \
          "Por favor menciona los nombres de los productos."
        ),
        state_patch: {
          "slots" => {
            "awaiting_comparison_items" => true
          }
        }
      )
    end

    def handle_product_availability(turn, state)
      respond(
        messages: text_message(
          "✅ Te ayudo a verificar la disponibilidad.\n\n" \
          "¿Qué producto estás buscando?"
        ),
        state_patch: {
          "slots" => {
            "awaiting_product_name" => true,
            "check_type" => "availability"
          }
        }
      )
    end

    def handle_product_categories(turn, state)
      respond(
        messages: list_message(
          body: "📂 Nuestras categorías de productos:",
          button_text: "Ver categorías",
          sections: [
            {
              title: "Categorías Principales",
              rows: [
                { id: "cat_food", title: "🍕 Comida", description: "Platos principales y especialidades" },
                { id: "cat_drinks", title: "🥤 Bebidas", description: "Refrescos, jugos y más" },
                { id: "cat_desserts", title: "🍰 Postres", description: "Dulces y delicias" },
                { id: "cat_sides", title: "🍟 Acompañamientos", description: "Guarniciones y extras" }
              ]
            }
          ]
        ),
        state_patch: {
          "dialogue" => {
            "last_category_view" => Time.now.utc.iso8601
          }
        }
      )
    end

    def handle_product_default(turn, state)
      respond(
        messages: text_message(
          "🛍️ Estás en la sección de productos.\n\n" \
          "¿Qué te gustaría saber?\n" \
          "• Ver categorías\n" \
          "• Detalles de producto\n" \
          "• Comparar productos\n" \
          "• Verificar disponibilidad"
        )
      )
    end
  end
end
