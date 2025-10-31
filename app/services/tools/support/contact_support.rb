# frozen_string_literal: true

module Tools
  module Support
    # ContactSupport tool for getting human support contact information
    # This tool does not require state access - it provides static contact information
    class ContactSupport < RubyLLM::Tool
      description "Get contact information for human support team. Provides phone numbers, email, hours, and expected response times."

      param :contact_type, type: :string, required: false,
            desc: "Type of contact: 'phone', 'email', 'whatsapp', 'all' (default: 'all')"
      param :urgency, type: :string, required: false,
            desc: "Urgency level: 'urgent', 'normal' (affects recommended contact method)"

      def initialize
        # Hard-coded contact information for MVP
        # TODO: Load from configuration or database
        @contact_info = {
          phone: {
            primary: "(555) 123-4567",
            toll_free: "1-800-TONYS-PIZZA",
            hours: "Lunes a Domingo: 9:00 AM - 10:00 PM",
            wait_time: "5-10 minutos",
            best_for: "Problemas urgentes, consultas complejas"
          },
          email: {
            general: "soporte@tonyspizza.com",
            refunds: "reembolsos@tonyspizza.com",
            complaints: "quejas@tonyspizza.com",
            response_time: "24-48 horas",
            best_for: "Consultas no urgentes, documentación detallada"
          },
          whatsapp: {
            number: "+57 300 123 4567",
            hours: "24/7 (respuesta automática fuera de horario)",
            response_time: "Inmediato (bot) o 10-15 min (humano)",
            best_for: "Preferencia de los clientes, acceso rápido"
          },
          hours: {
            weekday: "Lunes a Viernes: 9:00 AM - 10:00 PM",
            weekend: "Sábado y Domingo: 10:00 AM - 9:00 PM",
            holidays: "Horario reducido en días festivos"
          },
          escalation: {
            manager: "gerente@tonyspizza.com",
            corporate: "corporativo@tonyspizza.com",
            note: "Usar solo después de intentar canales regulares"
          }
        }
      end

      def execute(contact_type: "all", urgency: "normal")
        Rails.logger.info "[ContactSupport] Type: #{contact_type}, Urgency: #{urgency}"

        # Build response based on contact type
        case contact_type.downcase
        when "phone"
          format_phone_info(urgency)
        when "email"
          format_email_info(urgency)
        when "whatsapp"
          format_whatsapp_info
        when "all"
          format_all_info(urgency)
        else
          {
            error: "Invalid contact_type '#{contact_type}'",
            available_types: [ "phone", "email", "whatsapp", "all" ]
          }
        end
      rescue StandardError => e
        Rails.logger.error "[ContactSupport] Error: #{e.message}"
        { error: "Error fetching contact info: #{e.message}" }
      end

      private

      def format_phone_info(urgency)
        phone = @contact_info[:phone]
        {
          contact_type: "phone",
          recommended: urgency == "urgent",
          phone_numbers: {
            primary: phone[:primary],
            toll_free: phone[:toll_free]
          },
          hours: phone[:hours],
          wait_time: phone[:wait_time],
          best_for: phone[:best_for],
          message: urgency == "urgent" ?
            "📞 Para problemas urgentes, llama a #{phone[:primary]}" :
            "📞 Teléfono: #{phone[:primary]} (#{phone[:hours]})"
        }
      end

      def format_email_info(urgency)
        email = @contact_info[:email]
        {
          contact_type: "email",
          recommended: urgency == "normal",
          email_addresses: {
            general: email[:general],
            refunds: email[:refunds],
            complaints: email[:complaints]
          },
          response_time: email[:response_time],
          best_for: email[:best_for],
          message: "📧 Email: #{email[:general]} (respuesta en #{email[:response_time]})"
        }
      end

      def format_whatsapp_info
        wa = @contact_info[:whatsapp]
        {
          contact_type: "whatsapp",
          recommended: true,
          number: wa[:number],
          hours: wa[:hours],
          response_time: wa[:response_time],
          best_for: wa[:best_for],
          message: "💬 WhatsApp: #{wa[:number]} (#{wa[:response_time]})"
        }
      end

      def format_all_info(urgency)
        phone = @contact_info[:phone]
        email = @contact_info[:email]
        whatsapp = @contact_info[:whatsapp]

        # Recommend best method based on urgency
        recommended = if urgency == "urgent"
                        "phone"
        else
                        "whatsapp"
        end

        {
          contact_type: "all",
          recommended_method: recommended,
          urgency: urgency,
          contact_options: {
            phone: {
              primary: phone[:primary],
              toll_free: phone[:toll_free],
              hours: phone[:hours],
              wait_time: phone[:wait_time]
            },
            email: {
              general: email[:general],
              response_time: email[:response_time]
            },
            whatsapp: {
              number: whatsapp[:number],
              response_time: whatsapp[:response_time]
            }
          },
          business_hours: @contact_info[:hours],
          message: build_all_info_message(urgency, phone, email, whatsapp)
        }
      end

      def build_all_info_message(urgency, phone, email, whatsapp)
        if urgency == "urgent"
          "📞 Para problemas urgentes:\n" \
          "Teléfono: #{phone[:primary]}\n" \
          "WhatsApp: #{whatsapp[:number]}\n" \
          "Tiempo de espera: #{phone[:wait_time]}"
        else
          "Canales de contacto disponibles:\n\n" \
          "📞 Teléfono: #{phone[:primary]}\n" \
          "💬 WhatsApp: #{whatsapp[:number]} (recomendado)\n" \
          "📧 Email: #{email[:general]}\n\n" \
          "Horario: #{@contact_info[:hours][:weekday]}"
        end
      end
    end
  end
end
