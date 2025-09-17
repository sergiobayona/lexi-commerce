module Whatsapp
  module Intent
    # Evaluates intent and handles appropriate responses directly.
    class Handler
      def initialize(value:, msg:)
        @value = value
        @msg = msg
      end

      # Evaluate intent and run side-effecting follow-ups when appropriate.
      # Returns the evaluator result for callers that want to inspect it.
      def call
        result = Evaluator.new(value: @value, msg: @msg).call

        # Direct intent handling - simple and clear
        if greeting_intent?(result)
          handle_greeting_intent
        end

        result
      end

      private

      def greeting_intent?(result)
        result.is_a?(Hash) &&
          result[:label] == :onboard_greeting &&
          result[:confidence].to_f >= 0.8
      end

      def handle_greeting_intent
        contact, business_number = resolve_entities
        return log_missing_entities unless contact && business_number

        greeting_text = extract_greeting_text
        Whatsapp::Responders::WelcomeResponder.new(
          contact: contact,
          business_number: business_number
        ).call(greeting_text: greeting_text)
      end

      def resolve_entities
        # Simple entity resolution (extracted from Context.build)
        message = WaMessage.find_by(provider_message_id: @msg["id"]) rescue nil
        contact = message&.wa_contact || WaContact.find_by(wa_id: @value.dig("contacts", 0, "wa_id"))
        business_number = message&.wa_business_number || WaBusinessNumber.find_by(phone_number_id: @value.dig("metadata", "phone_number_id"))

        [ contact, business_number ]
      end

      def extract_greeting_text
        # Simple text extraction
        WaMessage.find_by(provider_message_id: @msg["id"])&.body_text || @msg.dig("text", "body")
      end

      def log_missing_entities
        Rails.logger.warn({
          at: "welcome_responder.skipped",
          reason: "missing_contact_or_business_number",
          msg_id: @msg["id"]
        }.to_json)
      end
    end
  end
end
