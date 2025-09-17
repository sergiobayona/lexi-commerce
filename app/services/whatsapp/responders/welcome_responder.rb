# frozen_string_literal: true

module Whatsapp
  module Responders
    class WelcomeResponder
      include BaseResponder

      def initialize(contact:, business_number:)
        @contact = contact
        @business_number = business_number
      end

      # Sends a friendly welcome message to the contact and records it.
      #
      # Options:
      # - greeting_text: the original greeting text to determine language
      # - text: override default welcome text
      # - preview_url: whether WhatsApp should auto-preview URLs
      #
      # Returns the created WaMessage record.
      def call(greeting_text: nil, text: nil, preview_url: false)
        raise ArgumentError, "contact not found" unless @contact
        raise ArgumentError, "business_number not found" unless @business_number

        name = @contact&.profile_name

        message_text = determine_welcome_message(greeting_text, name)

        api_res = send_text!(
          to: @contact.wa_id,
          body: message_text,
          business_number: @business_number,
          preview_url: preview_url
        )

        provider_id = Array(api_res.dig("messages")).first&.dig("id")
        record_outbound_message!(
          wa_contact: @contact,
          wa_business_number: @business_number,
          body: message_text,
          provider_message_id: provider_id,
          raw: api_res.is_a?(Hash) ? api_res : { raw: api_res }
        )
      end

      private

      def determine_welcome_message(greeting_text, name)
        language = detect_language(greeting_text)

        case language
        when :spanish
          spanish_welcome_message(name)
        else
          english_welcome_message(name)
        end
      end

      def detect_language(text)
        return :spanish if spanish_greeting?(text)
        :english
      end

      def spanish_greeting?(text)
        spanish_patterns = [
          /\b(hola|buenos\s+d[íi]as|buenas\s+(tardes|noches)|saludos|qu[eé]\s+tal|c[óo]mo\s+est[aá]s)\b/i
        ]
        spanish_patterns.any? { |pattern| text =~ pattern }
      end

      def spanish_welcome_message(name)
        <<~SPANISH.strip
          ¡Hola #{name}! 👋 ¡Soy Lexi!

          Soy tu asistente de aprendizaje de inglés. Estoy aquí para ayudarte a practicar y mejorar tu pronunciación.

          📝 Puedes enviarme:
          • Mensajes de voz para practicar pronunciación
          • Texto para revisar gramática
          • Preguntas sobre inglés

          ¿En qué te gustaría practicar hoy?
        SPANISH
      end

      def english_welcome_message(name)
        <<~ENGLISH.strip
          Hello #{name}! 👋 I'm Lexi!

          I'm your English learning assistant. I'm here to help you practice and improve your pronunciation.

          📝 You can send me:
          • Voice messages to practice pronunciation
          • Text to review grammar
          • Questions about English

          What would you like to practice today?
        ENGLISH
      end
    end
  end
end
