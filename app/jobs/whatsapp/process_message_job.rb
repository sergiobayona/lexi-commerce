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

    # After creating db records, do an initial (basic) evaluation
    # of the user's intent and run follow-ups.
    # We currently only handle th user's first message greeting intent.
    Whatsapp::Intent::Handler.new(value: value, msg: msg).call
  rescue => e
    Rails.logger.error({ at: "process_message.error", error: e.class.name, message: e.message }.to_json)
  end
end
