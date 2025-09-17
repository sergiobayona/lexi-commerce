class Whatsapp::ProcessMessageJob < ApplicationJob
  queue_as :default

  def perform(value, msg)
    type = msg["type"]
    case type
    when "text"
      Whatsapp::Processors::TextProcessor.new(value, msg).call
    when "audio"
      Whatsapp::Processors::AudioProcessor.new(value, msg).call
    else
      Whatsapp::Processors::BaseProcessor.new(value, msg).call # store raw, mark unknown
    end

    # After basic processing, evaluate the user's intent.
    # This is kept side-effect-free (no outbound send) and can later trigger follow-ups.
    Whatsapp::Intent::Evaluator.new(value: value, msg: msg).call
  end
end
