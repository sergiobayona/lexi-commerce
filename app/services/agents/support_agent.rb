# frozen_string_literal: true

module Agents
  # Support agent handles customer service, complaints, refunds, order issues
  class SupportAgent < BaseAgent
    def handle(turn:, state:, intent:)
      case intent
      when "order_status"
        handle_order_status(turn, state)
      when "refund_request"
        handle_refund_request(turn, state)
      when "complaint"
        handle_complaint(turn, state)
      when "technical_issue"
        handle_technical_issue(turn, state)
      when "cancel_order"
        handle_cancel_order(turn, state)
      when "human_handoff"
        handle_human_handoff(turn, state)
      else
        handle_support_default(turn, state)
      end
    end

    private

    def handle_order_status(turn, state)
      last_order_id = state.dig("support", "last_order_id")

      if last_order_id
        respond(
          messages: text_message(
            "📦 Estado de tu pedido ##{last_order_id}:\n\n" \
            "Estado: En preparación\n" \
            "Tiempo estimado: 30-45 minutos\n\n" \
            "Te notificaremos cuando esté en camino."
          ),
          state_patch: {
            "support" => {
              "last_status_check" => Time.now.utc.iso8601
            }
          }
        )
      else
        respond(
          messages: text_message(
            "Para revisar el estado de tu pedido, por favor compárteme el número de orden."
          ),
          state_patch: {
            "support" => { "awaiting_order_number" => true }
          }
        )
      end
    end

    def handle_refund_request(turn, state)
      respond(
        messages: text_message(
          "💰 Entiendo que solicitas un reembolso.\n\n" \
          "Para procesarlo necesito:\n" \
          "1. Número de orden\n" \
          "2. Motivo del reembolso\n\n" \
          "¿Puedes compartir esta información?"
        ),
        state_patch: {
          "support" => {
            "active_case_id" => "case_#{SecureRandom.hex(4)}",
            "case_type" => "refund",
            "opened_at" => Time.now.utc.iso8601
          },
          "slots" => {
            "awaiting_refund_details" => true
          }
        }
      )
    end

    def handle_complaint(turn, state)
      case_id = "case_#{SecureRandom.hex(4)}"

      respond(
        messages: text_message(
          "😔 Lamento que hayas tenido una mala experiencia.\n\n" \
          "He creado el caso ##{case_id} para darle seguimiento.\n\n" \
          "Por favor cuéntame qué ocurrió para poder ayudarte."
        ),
        state_patch: {
          "support" => {
            "active_case_id" => case_id,
            "case_type" => "complaint",
            "opened_at" => Time.now.utc.iso8601
          }
        }
      )
    end

    def handle_technical_issue(turn, state)
      respond(
        messages: button_message(
          body: "🔧 ¿Qué tipo de problema técnico estás experimentando?",
          buttons: [
            { id: "tech_payment", title: "Pago" },
            { id: "tech_app", title: "App/Web" },
            { id: "tech_other", title: "Otro" }
          ]
        ),
        state_patch: {
          "support" => {
            "active_case_id" => "case_#{SecureRandom.hex(4)}",
            "case_type" => "technical",
            "opened_at" => Time.now.utc.iso8601
          }
        }
      )
    end

    def handle_cancel_order(turn, state)
      respond(
        messages: text_message(
          "❌ Para cancelar tu pedido necesito el número de orden.\n\n" \
          "Ten en cuenta que solo podemos cancelar pedidos que aún no han sido enviados."
        ),
        state_patch: {
          "support" => {
            "active_case_id" => "case_#{SecureRandom.hex(4)}",
            "case_type" => "cancellation",
            "awaiting_order_number" => true
          }
        }
      )
    end

    def handle_human_handoff(turn, state)
      respond(
        messages: text_message(
          "👤 Entiendo que prefieres hablar con una persona.\n\n" \
          "Te estoy conectando con un agente humano. " \
          "El tiempo de espera estimado es de 5-10 minutos.\n\n" \
          "Por favor mantente en línea."
        ),
        state_patch: {
          "meta" => {
            "flags" => {
              "human_handoff" => true
            }
          },
          "support" => {
            "active_case_id" => "case_#{SecureRandom.hex(4)}",
            "case_type" => "human_handoff",
            "handoff_requested_at" => Time.now.utc.iso8601
          }
        }
      )
    end

    def handle_support_default(turn, state)
      respond(
        messages: list_message(
          body: "🆘 ¿Cómo puedo ayudarte?",
          button_text: "Ver opciones",
          sections: [
            {
              title: "Soporte",
              rows: [
                { id: "support_order", title: "Estado de pedido", description: "Rastrea tu orden" },
                { id: "support_refund", title: "Reembolsos", description: "Solicita devolución" },
                { id: "support_issue", title: "Reportar problema", description: "Quejas y reclamos" },
                { id: "support_human", title: "Agente humano", description: "Hablar con persona" }
              ]
            }
          ]
        ),
        state_patch: {
          "support" => {
            "last_interaction" => Time.now.utc.iso8601
          }
        }
      )
    end
  end
end
