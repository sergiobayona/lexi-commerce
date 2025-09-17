module Whatsapp
  module Intent
    class Evaluator
      def initialize(value:, msg:)
        @value = value
        @msg = msg
      end

      def call
        message = WaMessage.find_by(provider_message_id: @msg["id"]) # created by processors
        return unless message

        contact = message.wa_contact
        first_time = first_interaction?(contact, message)

        intent = infer_intent(message, first_time: first_time)

        Rails.logger.info(
          {
            at: "intent.evaluated",
            provider_message_id: message.provider_message_id,
            contact_id: contact&.id,
            first_interaction: first_time,
            intent_label: intent[:label],
            confidence: intent[:confidence],
            rationale: intent[:rationale]
          }.to_json
        )

        intent
      rescue => e
        Rails.logger.error({ at: "intent.error", error: e.class.name, message: e.message }.to_json)
        nil
      end

      private
      def first_interaction?(contact, current_message)
        return true unless contact
        # Any prior inbound message from this contact before this message's timestamp?
        WaMessage
          .where(wa_contact_id: contact.id, direction: "inbound")
          .where("timestamp < ?", current_message.timestamp)
          .exists? ? false : true
      end

      def infer_intent(message, first_time:)
        body = (message.body_text || "").strip
        return greet_intent(first_time) if first_time && greeting?(body)

        # Simple rule-based intents for first pass
        rules = [
          { label: :help,        matcher: /\b(help|support|instructions|how to)\b/i },
          { label: :summarize,   matcher: /\b(summary|summarize|tl;dr|shorten)\b/i },
          { label: :extract,     matcher: /\bextract|pull out|key (facts|points)\b/i },
          { label: :translate,   matcher: /\btranslate|translation\b/i },
          { label: :upload_doc,  matcher: /\b(upload|send).*(pdf|doc|file|document)\b/i },
          { label: :voice_note,  matcher: /\bvoice note|audio\b/i }
        ]

        matched = rules.find { |r| body =~ r[:matcher] }
        if matched
          return { label: matched[:label], confidence: 0.7, rationale: "Matched pattern #{matched[:label]}" }
        end

        if first_time
          { label: :onboard_greeting, confidence: 0.6, rationale: "First interaction without clear keywords" }
        else
          { label: :unknown, confidence: 0.3, rationale: "No rule matched" }
        end
      end

      def greeting?(text)
        text =~ /\b(hi|hello|hey|hola|howdy|good (morning|afternoon|evening))\b/i
      end

      def greet_intent(first_time)
        if first_time
          { label: :onboard_greeting, confidence: 0.8, rationale: "Greeting on first interaction" }
        else
          { label: :greeting, confidence: 0.7, rationale: "Greeting mid-conversation" }
        end
      end
    end
  end
end

