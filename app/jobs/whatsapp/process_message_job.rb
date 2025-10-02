class Whatsapp::ProcessMessageJob < ApplicationJob
  queue_as :default

  def perform(value, msg, webhook_event_id = nil)
    webhook_event = webhook_event_id ? WebhookEvent.find_by(id: webhook_event_id) : nil

    # Check for message-level errors (unsupported messages)
    if msg["errors"].present? || msg["type"] == "unsupported"
      process_message_error(msg, webhook_event)
      return
    end

    type = msg["type"]
    message_record = case type
    when "text"
      Whatsapp::Processors::TextProcessor.new(value, msg).call
    when "audio"
      Whatsapp::Processors::AudioProcessor.new(value, msg).call
    when "button"
        Whatsapp::Processors::ButtonProcessor.new(value, msg).call
    when "contacts"
        Whatsapp::Processors::ContactProcessor.new(value, msg).call
    when "document"
        Whatsapp::Processors::DocumentProcessor.new(value, msg).call
    when "location"
        Whatsapp::Processors::LocationProcessor.new(value, msg).call
    else
        Whatsapp::Processors::BaseProcessor.new(value, msg).call # store raw, mark unknown
    end




  rescue => e
    Rails.logger.error({ at: "process_message.error", error: e.class.name, message: e.message }.to_json)
  end

  private

  def process_message_error(msg, webhook_event)
    # Find or create a minimal message record for unsupported messages
    wa_message = WaMessage.find_by(provider_message_id: msg["id"])

    # Process the error
    Whatsapp::Processors::ErrorProcessor.process_message_error(msg, wa_message, webhook_event)

    Rails.logger.warn({
      at: "process_message.unsupported",
      provider_message_id: msg["id"],
      message_type: msg["type"],
      errors: msg["errors"]
    }.to_json)
  end
end
