# frozen_string_literal: true

module Agents
  # OrderStatusAgent handles order tracking, shipping updates, and delivery ETAs
  #
  # Responsibilities:
  # - Verify customer identity before providing order information
  # - Query Order Management System (OMS) for order details
  # - Provide shipping status and tracking information
  # - Deliver estimated delivery dates
  # - Handle order-related inquiries
  #
  # Intent patterns:
  # - "track_order": Customer wants to track an order
  # - "order_status": Check status of a recent order
  # - "delivery_eta": When will my order arrive?
  # - "shipping_update": Get latest shipping information
  class OrderStatusAgent < BaseAgent
    def handle(turn:, state:, intent:)
      case intent
      when "track_order"
        handle_order_tracking(turn, state)
      when "order_status"
        handle_order_status(turn, state)
      when "delivery_eta"
        handle_delivery_eta(turn, state)
      when "shipping_update"
        handle_shipping_update(turn, state)
      else
        handle_general_order_inquiry(turn, state)
      end
    end

    private

    def handle_order_tracking(turn, state)
      # Check if customer identity is verified
      unless verified_customer?(state)
        return request_verification(state)
      end

      # Extract order number from message if present
      order_number = extract_order_number(turn[:text])

      if order_number
        query_order_status(order_number, state)
      else
        request_order_number(state)
      end
    end

    def handle_order_status(turn, state)
      unless verified_customer?(state)
        return request_verification(state)
      end

      # Get most recent order for verified customer
      if state["last_order_id"]
        query_order_status(state["last_order_id"], state)
      else
        respond(
          messages: [text_message("No tiene órdenes recientes. ¿Tiene un número de orden específico que desea rastrear?")],
          state_patch: {}
        )
      end
    end

    def handle_delivery_eta(turn, state)
      unless verified_customer?(state)
        return request_verification(state)
      end

      # For now, provide estimated delivery window
      # TODO: Integrate with actual OMS to get real ETAs
      respond(
        messages: [ text_message("Su pedido está en camino. Tiempo estimado de entrega: 2-3 días hábiles. Le notificaremos cuando esté cerca de su ubicación.") ],
        state_patch: { "last_interaction" => Time.now.utc.iso8601 }
      )
    end

    def handle_shipping_update(turn, state)
      unless verified_customer?(state)
        return request_verification(state)
      end

      # TODO: Integrate with shipping provider API
      respond(
        messages: [ text_message("Su pedido fue enviado. Número de rastreo: TRACK123456. Puede rastrearlo en el sitio web del transportista.") ],
        state_patch: { "last_interaction" => Time.now.utc.iso8601 }
      )
    end

    def handle_general_order_inquiry(turn, state)
      respond(
        messages: [ text_message("Puedo ayudarle con:\n• Rastrear su orden\n• Verificar estado de entrega\n• Obtener tiempo estimado de llegada\n\n¿Qué necesita saber?") ],
        state_patch: {}
      )
    end

    def verified_customer?(state)
      # Check if phone is verified and customer ID is present
      state["phone_verified"] && state["customer_id"].present?
    end

    def request_verification(state)
      respond(
        messages: [ text_message("Para consultar información de su orden, necesito verificar su identidad. Por favor, proporcione el código de verificación enviado a su teléfono.") ],
        state_patch: { "verification_requested" => true }
      )
    end

    def request_order_number(state)
      respond(
        messages: [ text_message("Por favor, proporcione el número de su orden. Lo puede encontrar en su correo de confirmación.") ],
        state_patch: {}
      )
    end

    def query_order_status(order_id, state)
      # TODO: Integrate with actual OMS
      # For now, return a mock response
      respond(
        messages: [ text_message("Orden ##{order_id}:\n📦 Estado: En tránsito\n🚚 Transportista: DHL\n📍 Última ubicación: Bogotá\n⏰ Entrega estimada: Mañana antes de las 6pm") ],
        state_patch: {
          "last_order_checked" => order_id,
          "last_interaction" => Time.now.utc.iso8601
        }
      )
    end

    def extract_order_number(text)
      # Extract order number patterns like #12345, ORD-12345, etc.
      text.match(/#?(\w+[-]?\d+)/i)&.captures&.first
    end
  end
end
