# frozen_string_literal: true

module Tools
  module Order
    # ShippingStatus tool for tracking shipment status and location
    # Provides real-time tracking information and delivery updates
    class ShippingStatus < RubyLLM::Tool
      description "Get real-time shipping status and tracking information. Shows current location, delivery progress, and estimated arrival time."

      param :tracking_number, type: :string, required: false,
            desc: "Tracking number (if not provided, uses last looked up order)"
      param :order_id, type: :string, required: false,
            desc: "Order ID to get tracking for (alternative to tracking_number)"

      def initialize(order_accessor_provider)
        @order_accessor_provider = order_accessor_provider

        # Mock tracking database for MVP
        # TODO: Replace with actual carrier API integration
        @tracking_data = {
          "TRACK-ABC123" => {
            tracking_number: "TRACK-ABC123",
            order_id: "ORD-12345",
            carrier: "Delivery Express",
            status: "in_transit",
            status_display: "En tránsito",
            current_location: "Centro de distribución - Bogotá",
            last_update: "2025-01-28T11:45:00Z",
            estimated_delivery: "2025-01-28T12:30:00Z",
            delivery_attempts: 0,
            history: [
              {
                timestamp: "2025-01-28T10:30:00Z",
                location: "Restaurante - Bogotá",
                status: "Pedido recogido",
                description: "El repartidor recogió tu pedido"
              },
              {
                timestamp: "2025-01-28T11:00:00Z",
                location: "En ruta",
                status: "En tránsito",
                description: "Tu pedido está en camino"
              },
              {
                timestamp: "2025-01-28T11:45:00Z",
                location: "Centro de distribución - Bogotá",
                status: "En centro de distribución",
                description: "Llegó al centro de distribución"
              }
            ]
          },
          "TRACK-XYZ789" => {
            tracking_number: "TRACK-XYZ789",
            order_id: "ORD-9999",
            carrier: "Fast Delivery",
            status: "delivered",
            status_display: "Entregado",
            current_location: "Entregado",
            last_update: "2025-01-27T14:20:00Z",
            estimated_delivery: "2025-01-27T14:00:00Z",
            delivered_at: "2025-01-27T14:20:00Z",
            delivered_to: "Recepción",
            delivery_attempts: 1,
            history: [
              {
                timestamp: "2025-01-27T14:20:00Z",
                location: "Calle 123 #45-67",
                status: "Entregado",
                description: "Paquete entregado exitosamente"
              }
            ]
          }
        }

        # Map order IDs to tracking numbers
        @order_to_tracking = {
          "ORD-12345" => "TRACK-ABC123",
          "ORD-9999" => "TRACK-XYZ789"
        }
      end

      def execute(tracking_number: nil, order_id: nil)
        Rails.logger.info "[ShippingStatus] Tracking: #{tracking_number}, Order: #{order_id}"

        order_accessor = @order_accessor_provider.call

        # Determine tracking number
        tracking = resolve_tracking_number(tracking_number, order_id, order_accessor)

        unless tracking
          return {
            found: false,
            error: "No se proporcionó número de rastreo ni orden",
            message: "Por favor proporciona un número de rastreo o ID de orden para consultar el estado de envío"
          }
        end

        # Get tracking data
        tracking_info = @tracking_data[tracking]

        unless tracking_info
          return {
            found: false,
            error: "Número de rastreo '#{tracking}' no encontrado",
            message: "No pudimos encontrar información de rastreo para ese número. Verifica que el número sea correcto."
          }
        end

        # Build response
        {
          found: true,
          tracking: format_tracking_info(tracking_info),
          message: build_tracking_message(tracking_info)
        }
      rescue StandardError => e
        Rails.logger.error "[ShippingStatus] Error: #{e.message}"
        { error: "Error al consultar estado de envío: #{e.message}" }
      end

      private

      def resolve_tracking_number(tracking_number, order_id, order_accessor)
        # Use provided tracking number
        return tracking_number if tracking_number

        # Look up by order ID
        return @order_to_tracking[order_id] if order_id && @order_to_tracking[order_id]

        # Use last looked up order
        last_order = order_accessor.last_order_id
        return @order_to_tracking[last_order] if last_order

        nil
      end

      def format_tracking_info(info)
        result = {
          tracking_number: info[:tracking_number],
          order_id: info[:order_id],
          carrier: info[:carrier],
          status: info[:status_display],
          current_location: info[:current_location],
          last_update: info[:last_update],
          estimated_delivery: info[:estimated_delivery]
        }

        # Add delivery info if delivered
        if info[:status] == "delivered"
          result[:delivered_at] = info[:delivered_at]
          result[:delivered_to] = info[:delivered_to]
        end

        # Add history
        result[:history] = info[:history].map do |event|
          {
            time: event[:timestamp],
            location: event[:location],
            status: event[:status],
            description: event[:description]
          }
        end

        result
      end

      def build_tracking_message(info)
        message = "🚚 Rastreo: #{info[:tracking_number]}\n"
        message += "Transportista: #{info[:carrier]}\n\n"

        message += "📍 Estado actual: #{info[:status_display]}\n"
        message += "Ubicación: #{info[:current_location]}\n"

        if info[:status] == "delivered"
          delivered_time = Time.parse(info[:delivered_at])
          message += "\n✅ Entregado: #{delivered_time.strftime('%d/%m/%Y a las %H:%M')}\n"
          message += "Recibido por: #{info[:delivered_to]}"
        else
          estimated_time = Time.parse(info[:estimated_delivery])
          message += "\n⏰ Entrega estimada: #{estimated_time.strftime('%H:%M')}"
        end

        # Add recent history (last 2 events)
        if info[:history].any?
          message += "\n\n📋 Historial reciente:\n"
          info[:history].last(2).reverse.each do |event|
            time = Time.parse(event[:timestamp])
            message += "• #{time.strftime('%H:%M')} - #{event[:status]}\n"
          end
        end

        message
      end
    end
  end
end
