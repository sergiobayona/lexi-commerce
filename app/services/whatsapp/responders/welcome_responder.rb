module Whatsapp
  module Responders
    class WelcomeResponder
      def initialize(value, msg)
        @value = value
        @msg = msg
      end

      def call
        # Find the message and contact for context
        message = WaMessage.find_by(provider_message_id: @msg["id"])
        return unless message

        contact = message.wa_contact
        business_number = message.wa_business_number

        # Determine the appropriate welcome message based on language context
        welcome_text = determine_welcome_message(message.body_text)

        # Log the welcome response attempt
        Rails.logger.info({
          "at" => "welcome_responder.sending",
          "provider_message_id" => message.provider_message_id,
          "contact_wa_id" => contact&.wa_id,
          "welcome_language" => detect_language(message.body_text).to_s,
          "message_preview" => welcome_text[0..50]
        })

        # In a real implementation, this would send the message via WhatsApp API
        # For now, we'll just log what would be sent
        Rails.logger.info({
          "at" => "welcome_responder.would_send",
          "to" => contact&.wa_id,
          "from" => business_number&.display_phone_number,
          "message" => welcome_text
        })

        # TODO: Implement actual WhatsApp API sending
        # send_whatsapp_message(
        #   to: contact.wa_id,
        #   message: welcome_text,
        #   business_number: business_number
        # )

        welcome_text
      rescue => e
        Rails.logger.error({
          at: "welcome_responder.error",
          error: e.class.name,
          message: e.message,
          provider_message_id: @msg["id"]
        }.to_json)
        nil
      end

      private

      def determine_welcome_message(greeting_text)
        language = detect_language(greeting_text)

        case language
        when :spanish
          spanish_welcome_message
        when :mixed
          bilingual_welcome_message
        else
          english_welcome_message
        end
      end

      def detect_language(text)
        return :mixed if mixed_language_greeting?(text)
        return :spanish if spanish_greeting?(text)
        :english
      end

      def spanish_greeting?(text)
        spanish_patterns = [
          /\b(hola|buenos\s+d[íi]as|buenas\s+(tardes|noches)|saludos|qu[eé]\s+tal|c[óo]mo\s+est[aá]s)\b/i
        ]
        spanish_patterns.any? { |pattern| text =~ pattern }
      end

      def mixed_language_greeting?(text)
        mixed_patterns = [
          /hola.*how\s+are\s+you/i,
          /hi.*c[óo]mo\s+est[aáà]s/i,
          /hello.*qu[eé]\s+tal/i,
          /hey.*hola/i
        ]
        mixed_patterns.any? { |pattern| text =~ pattern }
      end

      def spanish_welcome_message
        <<~SPANISH
          ¡Hola! 👋 ¡Bienvenido/a a Lexi!

          Soy tu asistente de aprendizaje de inglés. Estoy aquí para ayudarte a practicar y mejorar tu pronunciación.

          📝 Puedes enviarme:
          • Mensajes de voz para practicar pronunciación
          • Texto para revisar gramática
          • Preguntas sobre inglés

          ¿En qué te gustaría practicar hoy?
        SPANISH
      end

      def bilingual_welcome_message
        <<~BILINGUAL
          ¡Hola! Hi! 👋 Welcome to Lexi!

          I'm your English learning assistant / Soy tu asistente de aprendizaje de inglés.

          📝 You can send me / Puedes enviarme:
          • Voice messages to practice pronunciation / Mensajes de voz para practicar pronunciación
          • Text to review grammar / Texto para revisar gramática
          • Questions about English / Preguntas sobre inglés

          What would you like to practice today? / ¿En qué te gustaría practicar hoy?
        BILINGUAL
      end

      def english_welcome_message
        <<~ENGLISH
          Hello! 👋 Welcome to Lexi!

          I'm your English learning assistant. I'm here to help you practice and improve your pronunciation.

          📝 You can send me:
          • Voice messages to practice pronunciation
          • Text to review grammar
          • Questions about English

          What would you like to practice today?
        ENGLISH
      end

      # TODO: Implement actual WhatsApp API integration
      # def send_whatsapp_message(to:, message:, business_number:)
      #   # Implementation would depend on WhatsApp Business API
      #   # This would make an HTTP request to send the message
      # end
    end
  end
end