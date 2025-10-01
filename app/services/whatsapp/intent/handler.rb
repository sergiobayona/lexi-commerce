module Whatsapp
  module Intent
    # Evaluates intent and handles appropriate responses directly.
    class Handler
      def initialize(value:, msg:)
        @value = value
        @msg = msg
      end

      def call
      end
    end
  end
end
