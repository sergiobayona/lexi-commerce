module Whatsapp
  module Nlp
    module Greetings
      module_function

      def greeting?(text)
        return false if text.to_s.strip.empty?
        simple_greetings_match?(text) || mixed_language_greetings_match?(text)
      end

      def detect_language(text)
        return :spanish if spanish_greeting?(text)
        :english
      end

      def spanish_greeting?(text)
        patterns = [
          /\b(hola|buenos\s+d[íi]as|buenas\s+(tardes|noches)|saludos|qu[eé]\s+tal|c[óo]mo\s+est[aá]s)\b/i
        ]
        patterns.any? { |pattern| text.to_s =~ pattern }
      end

      def simple_greetings_match?(text)
        patterns = [
          /\b(hi|hello|hey|howdy|yo|sup)\b/i,
          /\bgood\s+(morning|afternoon|evening|night)\b/i,
          /\bhola\b/i,
          /\bbuenos\s+d[íi]as?\b/i,
          /\bbuenas?\s+(tardes?|noches?)\b/i,
          /\b(buenas|buen\s+d[íi]a)\b/i,
          /\b(¿|que\s+)?c[óo]mo\s+(est[aáà]s?|andas?|te\s+va|va\s+todo|te\s+encuentras?)\b/i,
          /\b(¿|que\s+)?qu[eé]\s+(tal|pasa|onda|hubo|hay)\b/i,
          /\btodo\s+bien\b/i,
          /\b(saludos?|holi|holita|ey|oye)\b/i,
          /\b(qu[íi]hubo|quiubo)\b/i,
          /\bqu[eé]\s+m[aá]s\b/i,
          /\b(epale|[eé]palee?)\b/i,
          /\b(manin|pana|weón?|wey|g[üu]ey|bro|hermano?)\b/i,
          /\bmuy\s+buenos?\s+d[íi]as?\b/i,
          /\btengan?\s+buenos?\s+d[íi]as?\b/i,
          /\bque\s+tengas?\s+buen\s+d[íi]a\b/i,
          /\bcomo\s+(estas?|andas?)\b/i,
          /\bque\s+(tal|pasa)\b/i,
          /\bbuenos\s+dias?\b/i,
          /\bbuenas\s+(tardes?|noches?)\b/i,
          /\b[qk]\s+(tal|pasa|onda)\b/i,
          /\bxq\b/i,
          /\b(un\s+saludo|cordial\s+saludo)\b/i,
          /\b(muchachos?|gente|amigos?)\b/i
        ]
        patterns.any? { |pattern| text.to_s =~ pattern }
      end

      def mixed_language_greetings_match?(text)
        patterns = [
          /hola.*how\s+are\s+you/i,
          /hi.*c[óo]mo\s+est[aáà]s/i,
          /hello.*qu[eé]\s+tal/i,
          /hey.*hola/i
        ]
        patterns.any? { |pattern| text.to_s =~ pattern }
      end
    end
  end
end

