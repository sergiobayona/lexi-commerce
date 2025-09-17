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
          Whatsapp::Responders::WelcomeResponder.new(@value, @msg).call
        end

        result
      end

      private

      def onboarding_greeting?(result)
        return false unless result.is_a?(Hash)

        result[:label] == :onboard_greeting && (result[:confidence].to_f >= 0.8)
      end
    end
  end
end
