# frozen_string_literal: true

module Tools
  module Commerce
    # CartManager tool for managing shopping cart operations
    # Requires state access via CartAccessor for reading/modifying cart
    class CartManager < RubyLLM::Tool
      description "Manage shopping cart: view items, add products, update quantities, remove items, or clear cart. Returns cart summary and state updates."

      param :action, type: :string, required: true,
            desc: "Action to perform: 'view', 'add', 'remove', 'update_quantity', 'clear'"
      param :product_id, type: :string, required: false,
            desc: "Product ID for add/remove/update actions"
      param :quantity, type: :integer, required: false,
            desc: "Quantity for add/update actions (default: 1)"

      def initialize(cart_accessor_provider)
        @cart_accessor_provider = cart_accessor_provider
      end

      def execute(action:, product_id: nil, quantity: 1)
        Rails.logger.info "[CartManager] Action: #{action}, Product: #{product_id}, Quantity: #{quantity}"

        # Get cart accessor (provided by agent with current state)
        cart = @cart_accessor_provider.call

        case action.downcase
        when "view"
          view_cart(cart)
        when "add"
          add_to_cart(cart, product_id, quantity)
        when "remove"
          remove_from_cart(cart, product_id)
        when "update_quantity"
          update_cart_quantity(cart, product_id, quantity)
        when "clear"
          clear_cart(cart)
        else
          { error: "Invalid action '#{action}'. Valid actions: view, add, remove, update_quantity, clear" }
        end
      rescue StandardError => e
        Rails.logger.error "[CartManager] Error: #{e.message}"
        { error: "Cart operation failed: #{e.message}" }
      end

      private

      def view_cart(cart)
        summary = cart.summary

        if summary[:is_empty]
          {
            action: "view",
            cart: summary,
            message: "🛒 Tu carrito está vacío. ¿Te gustaría ver nuestros productos?"
          }
        else
          {
            action: "view",
            cart: summary,
            message: "🛒 Tu carrito tiene #{summary[:item_count]} #{summary[:item_count] == 1 ? 'producto' : 'productos'}. Subtotal: #{summary[:subtotal]}"
          }
        end
      end

      def add_to_cart(cart, product_id, quantity)
        return { error: "product_id is required for add action" } unless product_id
        return { error: "quantity must be positive" } if quantity <= 0

        # Fetch product info (in real app, would query product service)
        product_info = fetch_product_info(product_id)
        return { error: "Product '#{product_id}' not found" } unless product_info

        # Add item and get state patch
        state_patch = cart.add_item(
          product_id: product_id,
          quantity: quantity,
          product_info: product_info
        )

        {
          action: "add",
          success: true,
          product: {
            id: product_id,
            name: product_info[:name],
            quantity: quantity,
            price: "$#{product_info[:price_cents] / 100}"
          },
          cart: cart.summary,
          message: "✅ #{product_info[:name]} agregado al carrito (x#{quantity})",
          state_patch: state_patch
        }
      end

      def remove_from_cart(cart, product_id)
        return { error: "product_id is required for remove action" } unless product_id

        items = cart.get_items
        item = items.find { |i| i["id"] == product_id }
        return { error: "Product '#{product_id}' not found in cart" } unless item

        state_patch = cart.remove_item(product_id: product_id)

        {
          action: "remove",
          success: true,
          removed_item: item["name"],
          cart: cart.summary,
          message: "🗑️ #{item['name']} eliminado del carrito",
          state_patch: state_patch
        }
      end

      def update_cart_quantity(cart, product_id, quantity)
        return { error: "product_id is required for update_quantity action" } unless product_id
        return { error: "quantity must be non-negative" } if quantity < 0

        items = cart.get_items
        item = items.find { |i| i["id"] == product_id }
        return { error: "Product '#{product_id}' not found in cart" } unless item

        state_patch = cart.update_quantity(product_id: product_id, quantity: quantity)

        message = if quantity.zero?
                    "🗑️ #{item['name']} eliminado del carrito"
        else
                    "✏️ Cantidad actualizada: #{item['name']} x#{quantity}"
        end

        {
          action: "update_quantity",
          success: true,
          product_id: product_id,
          new_quantity: quantity,
          cart: cart.summary,
          message: message,
          state_patch: state_patch
        }
      end

      def clear_cart(cart)
        was_empty = cart.empty?
        state_patch = cart.clear

        {
          action: "clear",
          success: true,
          cart: { item_count: 0, items: [], subtotal: "$0", is_empty: true },
          message: was_empty ? "El carrito ya estaba vacío" : "🗑️ Carrito vaciado",
          state_patch: state_patch
        }
      end

      # Mock product fetching (in real app, would use ProductService)
      def fetch_product_info(product_id)
        products = {
          "prod_001" => { name: "Pizza Margherita", price_cents: 12000 },
          "prod_002" => { name: "Pizza Pepperoni", price_cents: 14000 },
          "prod_003" => { name: "Coca-Cola 500ml", price_cents: 3000 },
          "prod_004" => { name: "Tiramisu", price_cents: 8000 },
          "prod_005" => { name: "Pizza Vegetariana", price_cents: 13000 }
        }
        products[product_id]
      end
    end
  end
end
