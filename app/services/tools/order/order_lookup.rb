# frozen_string_literal: true

module Tools
  module Order
    # OrderLookup tool for searching and retrieving order information
    # Requires verification before providing order details for security
    class OrderLookup < RubyLLM::Tool
      description "Look up order information by order ID. Requires customer verification for security. Returns order status, items, and tracking information."

      param :order_id, type: :string, required: true,
            desc: "Order ID or tracking number (e.g., 'ORD-12345', '#8A73')"
      param :phone, type: :string, required: false,
            desc: "Customer phone number for verification (last 4 digits acceptable)"

      def initialize(order_accessor_provider, state_provider)
        @order_accessor_provider = order_accessor_provider
        @state_provider = state_provider

        # Mock order database for MVP
        # TODO: Replace with actual OMS integration
        @orders = {
          "ORD-12345" => {
            order_id: "ORD-12345",
            customer_phone: "+573001234567",
            customer_name: "María García",
            status: "in_transit",
            status_display: "En tránsito",
            created_at: "2025-01-28T10:30:00Z",
            items: [
              { name: "Pizza Margherita", quantity: 2, price_cents: 24000 },
              { name: "Coca-Cola 500ml", quantity: 2, price_cents: 6000 }
            ],
            subtotal_cents: 30000,
            delivery_address: "Calle 123 #45-67, Bogotá",
            estimated_delivery: "2025-01-28T12:30:00Z",
            tracking_number: "TRACK-ABC123",
            carrier: "Delivery Express"
          },
          "ORD-8A73" => {
            order_id: "ORD-8A73",
            customer_phone: "+573009876543",
            customer_name: "Juan Pérez",
            status: "preparing",
            status_display: "En preparación",
            created_at: "2025-01-28T11:00:00Z",
            items: [
              { name: "Pizza Pepperoni", quantity: 1, price_cents: 14000 },
              { name: "Tiramisu", quantity: 1, price_cents: 8000 }
            ],
            subtotal_cents: 22000,
            delivery_address: "Carrera 7 #50-22, Bogotá",
            estimated_delivery: "2025-01-28T12:00:00Z",
            tracking_number: nil,
            carrier: nil
          }
        }
      end

      def execute(order_id:, phone: nil)
        Rails.logger.info "[OrderLookup] Looking up order: #{order_id}, phone: #{phone ? '[provided]' : '[not provided]'}"

        order_accessor = @order_accessor_provider.call
        state = @state_provider.call

        # Normalize order ID
        normalized_id = normalize_order_id(order_id)
        order = find_order(normalized_id)

        unless order
          return {
            found: false,
            error: "Orden '#{order_id}' no encontrada",
            message: "No pudimos encontrar una orden con ese número. Por favor verifica el número de orden."
          }
        end

        # Check verification
        unless can_access_order?(order, phone, order_accessor, state)
          return request_verification(order_id)
        end

        # Record successful lookup
        state_patch = order_accessor.record_lookup(
          order_id: normalized_id,
          result: { status: order[:status] }
        )
        state_patch = state_patch.deep_merge(
          order_accessor.add_to_history(order_id: normalized_id)
        )

        # Build response
        {
          found: true,
          order: format_order_details(order),
          message: build_order_message(order),
          state_patch: state_patch
        }
      rescue StandardError => e
        Rails.logger.error "[OrderLookup] Error: #{e.message}"
        { error: "Error al buscar orden: #{e.message}" }
      end

      private

      def normalize_order_id(order_id)
        # Remove # and whitespace, convert to uppercase
        cleaned = order_id.to_s.strip.gsub(/^#/, "").upcase

        # Try to match against known orders
        @orders.keys.find { |key| key.include?(cleaned) } || "ORD-#{cleaned}"
      end

      def find_order(order_id)
        @orders[order_id]
      end

      def can_access_order?(order, phone, order_accessor, state)
        # Already verified
        return true if order_accessor.verified?

        # Phone is verified and customer_id matches
        return true if order_accessor.can_access_without_verification?

        # Phone provided and matches order
        if phone
          return verify_phone(order[:customer_phone], phone)
        end

        false
      end

      def verify_phone(order_phone, provided_phone)
        # Remove non-digits from both
        order_digits = order_phone.gsub(/\D/, "")
        provided_digits = provided_phone.gsub(/\D/, "")

        # Allow last 4 digits match
        if provided_digits.length == 4
          return order_digits.end_with?(provided_digits)
        end

        # Full phone match
        order_digits == provided_digits
      end

      def request_verification(order_id)
        {
          found: false,
          requires_verification: true,
          order_id: order_id,
          message: "🔒 Para seguridad, necesito verificar tu identidad.\n\n" \
                   "Por favor proporciona:\n" \
                   "• Los últimos 4 dígitos de tu teléfono\n" \
                   "O\n" \
                   "• El teléfono completo asociado con la orden"
        }
      end

      def format_order_details(order)
        {
          order_id: order[:order_id],
          status: order[:status_display],
          created_at: order[:created_at],
          items: order[:items],
          total: "$#{order[:subtotal_cents] / 100}",
          delivery_address: order[:delivery_address],
          estimated_delivery: order[:estimated_delivery],
          tracking: order[:tracking_number] ? {
            tracking_number: order[:tracking_number],
            carrier: order[:carrier]
          } : nil
        }
      end

      def build_order_message(order)
        message = "📦 Orden #{order[:order_id]}\n\n"
        message += "Estado: #{order[:status_display]}\n"
        message += "Total: $#{order[:subtotal_cents] / 100}\n"

        if order[:tracking_number]
          message += "🚚 Rastreo: #{order[:tracking_number]} (#{order[:carrier]})\n"
        end

        if order[:estimated_delivery]
          delivery_time = Time.parse(order[:estimated_delivery])
          message += "📅 Entrega estimada: #{delivery_time.strftime('%H:%M')}\n"
        end

        message += "\nDirección: #{order[:delivery_address]}"
        message
      end
    end
  end
end
