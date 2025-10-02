# frozen_string_literal: true

module Agents
  # Info agent handles general information queries, business hours, FAQs, etc.
  class InfoAgent < BaseAgent
    def handle(turn:, state:, intent:)
      case intent
      when "business_hours"
        handle_business_hours(turn, state)
      when "location_info"
        handle_location_info(turn, state)
      when "general_faq"
        handle_general_faq(turn, state)
      when "start_shopping"
        # User wants to shop - handoff to commerce
        handoff_to_commerce(turn, state)
      when "get_support"
        # User needs help - handoff to support
        handoff_to_support(turn, state)
      else
        handle_general_info(turn, state)
      end
    end

    private

    def handle_business_hours(turn, state)
      respond(
        messages: text_message(
          "📅 Nuestro horario de atención:\n\n" \
          "Lunes a Viernes: 9:00 AM - 6:00 PM\n" \
          "Sábados: 10:00 AM - 2:00 PM\n" \
          "Domingos: Cerrado"
        ),
        state_patch: {
          "slots" => { "last_query" => "business_hours" }
        }
      )
    end

    def handle_location_info(turn, state)
      respond(
        messages: button_message(
          body: "📍 Tenemos 3 ubicaciones en Bogotá. ¿Cuál te queda más cerca?",
          buttons: [
            { id: "location_norte", title: "Zona Norte" },
            { id: "location_centro", title: "Centro" },
            { id: "location_sur", title: "Zona Sur" }
          ]
        ),
        state_patch: {
          "slots" => { "awaiting_location_choice" => true }
        }
      )
    end

    def handle_general_faq(turn, state)
      respond(
        messages: list_message(
          body: "¿En qué puedo ayudarte? Selecciona un tema:",
          button_text: "Ver opciones",
          sections: [
            {
              title: "Información General",
              rows: [
                { id: "faq_hours", title: "Horarios", description: "Horarios de atención" },
                { id: "faq_location", title: "Ubicación", description: "Nuestras sedes" },
                { id: "faq_delivery", title: "Envíos", description: "Info de domicilios" }
              ]
            }
          ]
        )
      )
    end

    def handoff_to_commerce(turn, state)
      respond(
        messages: text_message(
          "¡Perfecto! Te ayudo con tu pedido. Un momento..."
        ),
        handoff: handoff_to(
          lane: "commerce",
          carry_state: {
            "slots" => { "initiated_from" => "info" }
          }
        )
      )
    end

    def handoff_to_support(turn, state)
      respond(
        messages: text_message(
          "Entiendo que necesitas ayuda. Te conecto con soporte..."
        ),
        handoff: handoff_to(
          lane: "support",
          carry_state: {
            "slots" => { "initiated_from" => "info" }
          }
        )
      )
    end

    def handle_general_info(turn, state)
      respond(
        messages: text_message(
          "👋 ¡Hola! Soy tu asistente virtual.\n\n" \
          "Puedo ayudarte con:\n" \
          "• Información general\n" \
          "• Hacer pedidos\n" \
          "• Soporte y ayuda\n\n" \
          "¿Qué necesitas hoy?"
        ),
        state_patch: {
          "dialogue" => {
            "last_info_interaction" => Time.now.utc.iso8601
          }
        }
      )
    end
  end
end
