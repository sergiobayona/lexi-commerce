module Whatsapp
  module Intent
    # Small service object that evaluates intent and performs follow-ups
    # extracted from ProcessMessageJob to keep jobs thin and make behavior testable.
    class Handler
      def initialize(value:, msg:)
        @value = value
        @msg = msg
      end

      # Evaluate intent and run side-effecting follow-ups when appropriate.
      # Returns the evaluator result for callers that want to inspect it.
      def call
        result = Evaluator.new(value: @value, msg: @msg).call

        if onboarding_greeting?(result)
          contact, business_number = resolve_contact_and_number(@value, @msg)
          if contact && business_number
            # Get the original greeting text to determine appropriate language response
            message = WaMessage.find_by(provider_message_id: @msg["id"])
            greeting_text = message&.body_text || @msg.dig("text", "body")

            Whatsapp::Responders::WelcomeResponder.new(
              contact: contact,
              business_number: business_number
            ).call(greeting_text: greeting_text)
          else
            Rails.logger.warn({ at: "welcome_responder.skipped", reason: "missing_contact_or_business_number", msg_id: @msg["id"] }.to_json)
          end
        end

        result
      end

      private

      def onboarding_greeting?(result)
        return false unless result.is_a?(Hash)

        result[:label] == :onboard_greeting && (result[:confidence].to_f >= 0.8)
      end

      def resolve_contact_and_number(value, msg)
        # Prefer the just-persisted message associations
        message = WaMessage.find_by(provider_message_id: msg["id"]) rescue nil
        contact = message&.wa_contact
        business_number = message&.wa_business_number

        # Fallback to payload-based lookup
        contact ||= WaContact.find_by(wa_id: value.dig("contacts", 0, "wa_id"))
        business_number ||= WaBusinessNumber.find_by(phone_number_id: value.dig("metadata", "phone_number_id"))

        [contact, business_number]
      end
    end
  end
end
