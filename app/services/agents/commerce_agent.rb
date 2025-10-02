# frozen_string_literal: true

module Agents
  # Commerce agent handles shopping cart, orders, product browsing, checkout
  class CommerceAgent < BaseAgent
    def handle(turn:, state:, intent:)
      case intent
      when "start_order", "browse_products"
        handle_start_shopping(turn, state)
      when "add_to_cart"
        handle_add_to_cart(turn, state)
      when "view_cart"
        handle_view_cart(turn, state)
      when "checkout"
        handle_checkout(turn, state)
      when "product_inquiry"
        handle_product_inquiry(turn, state)
      else
        handle_commerce_default(turn, state)
      end
    end

    private

    def handle_start_shopping(turn, state)
      respond(
        messages: list_message(
          body: "🛍️ ¿Qué te gustaría ordenar hoy?",
          button_text: "Ver categorías",
          sections: [
            {
              title: "Categorías Populares",
              rows: [
                { id: "cat_food", title: "🍕 Comida", description: "Platos principales" },
                { id: "cat_drinks", title: "🥤 Bebidas", description: "Refrescos y más" },
                { id: "cat_desserts", title: "🍰 Postres", description: "Dulces delicias" }
              ]
            }
          ]
        ),
        state_patch: {
          "commerce" => {
            "state" => "browsing",
            "last_interaction" => Time.now.utc.iso8601
          }
        }
      )
    end

    def handle_add_to_cart(turn, state)
      # Simplified cart logic - in production, parse payload for actual item
      cart = state.dig("commerce", "cart") || { "items" => [], "subtotal_cents" => 0 }

      new_item = {
        "id" => "item_#{SecureRandom.hex(4)}",
        "name" => "Producto de ejemplo",
        "quantity" => 1,
        "price_cents" => 10000
      }

      cart["items"] << new_item
      cart["subtotal_cents"] += new_item["price_cents"]

      respond(
        messages: text_message(
          "✅ Agregado al carrito:\n" \
          "#{new_item['name']} x#{new_item['quantity']}\n\n" \
          "Subtotal: $#{cart['subtotal_cents'] / 100}\n\n" \
          "¿Deseas agregar algo más o proceder al pago?"
        ),
        state_patch: {
          "commerce" => {
            "cart" => cart,
            "state" => "cart_active"
          }
        }
      )
    end

    def handle_view_cart(turn, state)
      cart = state.dig("commerce", "cart")

      if cart.nil? || cart["items"].empty?
        respond(
          messages: text_message(
            "🛒 Tu carrito está vacío.\n\n" \
            "¿Te gustaría ver nuestro menú?"
          )
        )
      else
        cart_summary = cart["items"].map.with_index do |item, idx|
          "#{idx + 1}. #{item['name']} x#{item['quantity']} - $#{item['price_cents'] / 100}"
        end.join("\n")

        respond(
          messages: button_message(
            body: "🛒 Tu carrito:\n\n#{cart_summary}\n\nSubtotal: $#{cart['subtotal_cents'] / 100}",
            buttons: [
              { id: "checkout", title: "Pagar" },
              { id: "keep_shopping", title: "Seguir comprando" },
              { id: "clear_cart", title: "Vaciar carrito" }
            ]
          ),
          state_patch: {
            "commerce" => { "state" => "reviewing_cart" }
          }
        )
      end
    end

    def handle_checkout(turn, state)
      cart = state.dig("commerce", "cart")

      if cart.nil? || cart["items"].empty?
        respond(
          messages: text_message("No tienes productos en el carrito para pagar.")
        )
      else
        respond(
          messages: text_message(
            "💳 Procesando tu pedido...\n\n" \
            "Total: $#{cart['subtotal_cents'] / 100}\n\n" \
            "¿Confirmas tu pedido?"
          ),
          state_patch: {
            "commerce" => {
              "state" => "checkout",
              "checkout_initiated_at" => Time.now.utc.iso8601
            },
            "slots" => {
              "awaiting_checkout_confirmation" => true
            }
          }
        )
      end
    end

    def handle_product_inquiry(turn, state)
      respond(
        messages: text_message(
          "📖 ¿Sobre qué producto necesitas información?\n\n" \
          "Puedo contarte sobre ingredientes, precios, disponibilidad, etc."
        ),
        state_patch: {
          "commerce" => { "state" => "product_inquiry" }
        }
      )
    end

    def handle_commerce_default(turn, state)
      respond(
        messages: text_message(
          "🛍️ Estás en la sección de compras.\n\n" \
          "¿Qué te gustaría hacer?\n" \
          "• Ver productos\n" \
          "• Revisar carrito\n" \
          "• Hacer pedido"
        )
      )
    end
  end
end
