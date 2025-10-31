# frozen_string_literal: true

module State
  module Accessors
    # CartAccessor provides controlled access to the cart state slice
    # Encapsulates cart operations and prevents direct state manipulation
    #
    # Usage:
    #   accessor = CartAccessor.new(state)
    #   items = accessor.get_items
    #   accessor.add_item("prod_001", 2)
    #   total = accessor.subtotal
    class CartAccessor
      def initialize(state)
        @state = state
        ensure_cart_initialized!
      end

      # Get all items in the cart
      # @return [Array<Hash>] Cart items with id, name, quantity, price_cents
      def get_items
        cart.dig("items") || []
      end

      # Get number of items in cart
      # @return [Integer] Total item count
      def item_count
        get_items.sum { |item| item["quantity"] || 0 }
      end

      # Get cart subtotal in cents
      # @return [Integer] Subtotal in cents
      def subtotal
        cart.dig("subtotal_cents") || 0
      end

      # Check if cart is empty
      # @return [Boolean]
      def empty?
        get_items.empty?
      end

      # Add item to cart (returns state patch for agent to apply)
      # @param product_id [String] Product ID
      # @param quantity [Integer] Quantity to add
      # @param product_info [Hash] Product details (name, price_cents)
      # @return [Hash] State patch to apply
      def add_item(product_id:, quantity:, product_info:)
        items = get_items.dup

        # Check if item already exists
        existing_item = items.find { |item| item["id"] == product_id }

        if existing_item
          # Update quantity
          existing_item["quantity"] += quantity
        else
          # Add new item
          items << {
            "id" => product_id,
            "name" => product_info[:name],
            "quantity" => quantity,
            "price_cents" => product_info[:price_cents]
          }
        end

        # Recalculate subtotal
        new_subtotal = items.sum { |item| item["quantity"] * item["price_cents"] }

        {
          "commerce" => {
            "cart" => {
              "items" => items,
              "subtotal_cents" => new_subtotal
            },
            "state" => "cart_active",
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Remove item from cart (returns state patch)
      # @param product_id [String] Product ID to remove
      # @return [Hash] State patch to apply
      def remove_item(product_id:)
        items = get_items.dup
        items.reject! { |item| item["id"] == product_id }

        # Recalculate subtotal
        new_subtotal = items.sum { |item| item["quantity"] * item["price_cents"] }

        {
          "commerce" => {
            "cart" => {
              "items" => items,
              "subtotal_cents" => new_subtotal
            },
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Update item quantity (returns state patch)
      # @param product_id [String] Product ID
      # @param quantity [Integer] New quantity (0 removes item)
      # @return [Hash] State patch to apply
      def update_quantity(product_id:, quantity:)
        return remove_item(product_id: product_id) if quantity <= 0

        items = get_items.dup
        item = items.find { |i| i["id"] == product_id }

        return { error: "Item not found in cart" } unless item

        item["quantity"] = quantity

        # Recalculate subtotal
        new_subtotal = items.sum { |item| item["quantity"] * item["price_cents"] }

        {
          "commerce" => {
            "cart" => {
              "items" => items,
              "subtotal_cents" => new_subtotal
            },
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Clear all items from cart (returns state patch)
      # @return [Hash] State patch to apply
      def clear
        {
          "commerce" => {
            "cart" => {
              "items" => [],
              "subtotal_cents" => 0
            },
            "state" => "browsing",
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Get formatted cart summary
      # @return [Hash] Formatted cart data for display
      def summary
        items = get_items
        {
          item_count: item_count,
          items: items.map do |item|
            {
              name: item["name"],
              quantity: item["quantity"],
              price: "$#{item["price_cents"] / 100}",
              subtotal: "$#{(item["quantity"] * item["price_cents"]) / 100}"
            }
          end,
          subtotal: "$#{subtotal / 100}",
          is_empty: empty?
        }
      end

      private

      def cart
        @state.dig("commerce", "cart") || {}
      end

      def ensure_cart_initialized!
        @state["commerce"] ||= {}
        @state["commerce"]["cart"] ||= { "items" => [], "subtotal_cents" => 0 }
      end
    end
  end
end
