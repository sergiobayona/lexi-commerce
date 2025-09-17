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
        # Check for simple greeting patterns
        simple_greetings_match?(text) || mixed_language_greetings_match?(text)
      end

      private

      def simple_greetings_match?(text)
        patterns = [
          # English greetings
          /\b(hi|hello|hey|howdy|yo|sup)\b/i,
          /\bgood\s+(morning|afternoon|evening|night)\b/i,

          # Spanish basic greetings
          /\bhola\b/i,
          /\bbuenos\s+d[íi]as?\b/i,
          /\bbuenas?\s+(tardes?|noches?)\b/i,
          /\b(buenas|buen\s+d[íi]a)\b/i,

          # Spanish "how are you" variations (with/without question marks)
          /\b(¿|que\s+)?c[óo]mo\s+(est[aáà]s?|andas?|te\s+va|va\s+todo|te\s+encuentras?)\b/i,
          /\b(¿|que\s+)?qu[eé]\s+(tal|pasa|onda|hubo|hay)\b/i,
          /\btodo\s+bien\b/i,

          # Casual Spanish greetings
          /\b(saludos?|holi|holita|ey|oye)\b/i,

          # Regional variations
          /\b(qu[íi]hubo|quiubo)\b/i,
          /\bqu[eé]\s+m[aá]s\b/i,
          /\b(epale|[eé]palee?)\b/i,
          /\b(manin|pana|weón?|wey|g[üu]ey|bro|hermano?)\b/i,

          # Formal Spanish greetings
          /\bmuy\s+buenos?\s+d[íi]as?\b/i,
          /\btengan?\s+buenos?\s+d[íi]as?\b/i,
          /\bque\s+tengas?\s+buen\s+d[íi]a\b/i,

          # Common variations without accents
          /\bcomo\s+(estas?|andas?)\b/i,
          /\bque\s+(tal|pasa)\b/i,
          /\bbuenos\s+dias?\b/i,
          /\bbuenas\s+(tardes?|noches?)\b/i,

          # Internet slang and abbreviations
          /\b[qk]\s+(tal|pasa|onda)\b/i,
          /\bxq\b/i,

          # Other variations
          /\b(un\s+saludo|cordial\s+saludo)\b/i,
          /\b(muchachos?|gente|amigos?)\b/i
        ]

        patterns.any? { |pattern| text =~ pattern }
      end

      def mixed_language_greetings_match?(text)
        mixed_patterns = [
          /hola.*how\s+are\s+you/i,
          /hi.*c[óo]mo\s+est[aáà]s/i,
          /hello.*qu[eé]\s+tal/i,
          /hey.*hola/i
        ]

        mixed_patterns.any? { |pattern| text =~ pattern }
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
