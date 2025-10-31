# frozen_string_literal: true

module Tools
  module Order
    # DeliveryEstimate tool for getting estimated delivery times
    # Provides ETA calculations based on order status and location
    class DeliveryEstimate < RubyLLM::Tool
      description "Get estimated delivery time for an order. Calculates ETA based on order status, preparation time, and delivery location."

      param :order_id, type: :string, required: false,
            desc: "Order ID to get estimate for (uses last order if not provided)"
      param :address, type: :string, required: false,
            desc: "Delivery address for new estimate calculation"

      def initialize(order_accessor_provider)
        @order_accessor_provider = order_accessor_provider

        # Mock order data for MVP
        # TODO: Replace with actual OMS integration
        @orders = {
          "ORD-12345" => {
            order_id: "ORD-12345",
            status: "in_transit",
            created_at: "2025-01-28T10:30:00Z",
            estimated_delivery: "2025-01-28T12:30:00Z",
            preparation_time_minutes: 20,
            delivery_time_minutes: 30,
            delivery_zone: "Zona Norte - Bogotá"
          },
          "ORD-8A73" => {
            order_id: "ORD-8A73",
            status: "preparing",
            created_at: "2025-01-28T11:00:00Z",
            estimated_delivery: "2025-01-28T12:00:00Z",
            preparation_time_minutes: 25,
            delivery_time_minutes: 35,
            delivery_zone: "Centro - Bogotá"
          }
        }
      end

      def execute(order_id: nil, address: nil)
        Rails.logger.info "[DeliveryEstimate] Order: #{order_id}, Address: #{address}"

        order_accessor = @order_accessor_provider.call

        # If address provided, calculate new estimate
        if address
          return calculate_new_estimate(address)
        end

        # Resolve order ID
        resolved_order_id = order_id || order_accessor.last_order_id

        unless resolved_order_id
          return {
            error: "No se especificó orden",
            message: "Por favor proporciona un número de orden o realiza una búsqueda de orden primero"
          }
        end

        # Get order
        order = @orders[resolved_order_id]

        unless order
          return {
            found: false,
            error: "Orden '#{resolved_order_id}' no encontrada",
            message: "No pudimos encontrar información de esa orden"
          }
        end

        # Build estimate response
        {
          found: true,
          order_id: order[:order_id],
          estimate: format_estimate(order),
          message: build_estimate_message(order)
        }
      rescue StandardError => e
        Rails.logger.error "[DeliveryEstimate] Error: #{e.message}"
        { error: "Error al calcular tiempo de entrega: #{e.message}" }
      end

      private

      def calculate_new_estimate(address)
        # Mock calculation based on address
        # TODO: Replace with actual distance/zone calculation

        # Extract zone from address (simplified)
        zone = if address.downcase.include?("norte")
                 "Zona Norte"
               elsif address.downcase.include?("sur")
                 "Zona Sur"
               elsif address.downcase.include?("centro")
                 "Centro"
               else
                 "Zona General"
               end

        # Base times
        prep_time = 20 # minutes
        delivery_time = case zone
                        when "Zona Norte" then 30
                        when "Zona Sur" then 45
                        when "Centro" then 35
                        else 40
                        end

        total_time = prep_time + delivery_time
        estimated_arrival = Time.now + (total_time * 60)

        {
          is_estimate: true,
          address: address,
          delivery_zone: zone,
          preparation_time: "#{prep_time} minutos",
          delivery_time: "#{delivery_time} minutos",
          total_time: "#{total_time} minutos",
          estimated_arrival: estimated_arrival.strftime("%H:%M"),
          message: "📍 Estimación para #{address}:\n\n" \
                   "• Preparación: #{prep_time} min\n" \
                   "• Entrega: #{delivery_time} min\n" \
                   "• Total: #{total_time} min\n\n" \
                   "⏰ Llegada estimada: #{estimated_arrival.strftime('%H:%M')}"
        }
      end

      def format_estimate(order)
        estimated_time = Time.parse(order[:estimated_delivery])
        now = Time.now
        minutes_remaining = ((estimated_time - now) / 60).round

        {
          order_id: order[:order_id],
          status: order[:status],
          estimated_delivery: order[:estimated_delivery],
          estimated_delivery_display: estimated_time.strftime("%H:%M"),
          minutes_remaining: minutes_remaining > 0 ? minutes_remaining : 0,
          preparation_time: order[:preparation_time_minutes],
          delivery_time: order[:delivery_time_minutes],
          delivery_zone: order[:delivery_zone],
          is_late: minutes_remaining < 0
        }
      end

      def build_estimate_message(order)
        estimated_time = Time.parse(order[:estimated_delivery])
        now = Time.now
        minutes_remaining = ((estimated_time - now) / 60).round

        message = "⏰ Estimación de entrega\n"
        message += "Orden: #{order[:order_id]}\n\n"

        if order[:status] == "delivered"
          message += "✅ Esta orden ya fue entregada"
        elsif order[:status] == "preparing"
          message += "👨‍🍳 Estado: En preparación\n"
          message += "Tiempo estimado: #{order[:preparation_time_minutes]} min\n"
          message += "Entrega: #{estimated_time.strftime('%H:%M')}"
        elsif order[:status] == "in_transit"
          if minutes_remaining > 0
            message += "🚚 En camino a tu ubicación\n"
            message += "Llegada: #{estimated_time.strftime('%H:%M')}\n"
            message += "Tiempo restante: ~#{minutes_remaining} min"
          else
            message += "🚚 Tu pedido debería llegar en cualquier momento\n"
            message += "Hora estimada: #{estimated_time.strftime('%H:%M')}"
          end
        else
          message += "Tiempo estimado de entrega: #{estimated_time.strftime('%H:%M')}\n"
          message += "Zona: #{order[:delivery_zone]}"
        end

        message
      end
    end
  end
end
