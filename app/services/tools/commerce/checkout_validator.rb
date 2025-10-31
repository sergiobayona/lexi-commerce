# frozen_string_literal: true

module Tools
  module Commerce
    # CheckoutValidator tool for validating checkout requirements
    # Requires state access to check cart and customer information
    class CheckoutValidator < RubyLLM::Tool
      description "Validate if customer can proceed to checkout. Checks cart status, customer info, and any business rules. Returns validation result and missing requirements."

      param :check_type, type: :string, required: false,
            desc: "Type of validation: 'full' (default), 'cart_only', 'customer_only'"

      def initialize(cart_accessor_provider, state_provider)
        @cart_accessor_provider = cart_accessor_provider
        @state_provider = state_provider
      end

      def execute(check_type: "full")
        Rails.logger.info "[CheckoutValidator] Validation type: #{check_type}"

        cart = @cart_accessor_provider.call
        state = @state_provider.call

        case check_type.downcase
        when "full"
          validate_full_checkout(cart, state)
        when "cart_only"
          validate_cart(cart)
        when "customer_only"
          validate_customer(state)
        else
          { error: "Invalid check_type '#{check_type}'. Valid types: full, cart_only, customer_only" }
        end
      rescue StandardError => e
        Rails.logger.error "[CheckoutValidator] Error: #{e.message}"
        { error: "Checkout validation failed: #{e.message}" }
      end

      private

      def validate_full_checkout(cart, state)
        cart_validation = validate_cart(cart)
        customer_validation = validate_customer(state)

        can_checkout = cart_validation[:valid] && customer_validation[:valid]

        missing_requirements = []
        missing_requirements += cart_validation[:issues] if cart_validation[:issues]
        missing_requirements += customer_validation[:issues] if customer_validation[:issues]

        {
          can_checkout: can_checkout,
          cart_valid: cart_validation[:valid],
          customer_valid: customer_validation[:valid],
          missing_requirements: missing_requirements,
          cart_summary: cart.summary,
          message: build_validation_message(can_checkout, missing_requirements)
        }
      end

      def validate_cart(cart)
        issues = []

        # Check if cart is empty
        if cart.empty?
          issues << "Cart is empty - add products before checkout"
        end

        # Check minimum order amount (example: $10,000)
        min_order_cents = 10_000
        if cart.subtotal < min_order_cents
          issues << "Minimum order is $#{min_order_cents / 100} (current: $#{cart.subtotal / 100})"
        end

        # Check item availability (simplified - in real app would check inventory)
        # For now, assume all items in cart are available

        {
          valid: issues.empty?,
          issues: issues,
          cart_value: "$#{cart.subtotal / 100}",
          item_count: cart.item_count
        }
      end

      def validate_customer(state)
        issues = []

        # Check if customer is identified
        unless state["customer_id"]
          issues << "Customer identification required"
        end

        # Check if phone is verified
        unless state["phone_verified"]
          issues << "Phone verification required"
        end

        # Check if customer has required info (would check delivery address, payment method, etc.)
        # For MVP, just check basic identification

        {
          valid: issues.empty?,
          issues: issues,
          customer_id: state["customer_id"],
          phone_verified: state["phone_verified"]
        }
      end

      def build_validation_message(can_checkout, missing_requirements)
        if can_checkout
          "✅ Todo listo para proceder al pago"
        else
          "⚠️ Requisitos faltantes:\n" + missing_requirements.map { |req| "• #{req}" }.join("\n")
        end
      end
    end
  end
end
