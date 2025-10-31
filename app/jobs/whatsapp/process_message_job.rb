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

    # Orchestrate conversation flow for eligible messages
    trigger_orchestration(message_record) if message_record

  rescue => e
    Rails.logger.error({
      at: "process_message.error",
      error: e.class.name,
      message: e.message,
      backtrace: e.backtrace
    }.to_json)

    # Output full exception details to STDOUT for debugging
    puts "\n" + "=" * 80
    puts "ERROR in ProcessMessageJob"
    puts "=" * 80
    puts "Exception: #{e.class.name}"
    puts "Message: #{e.message}"
    puts "\nBacktrace:"
    puts e.backtrace.join("\n")
    puts "=" * 80 + "\n"

    raise
  end

  private

  # Trigger orchestration for eligible message types
  def trigger_orchestration(wa_message)
    # Only orchestrate certain message types in Phase 1
    return unless orchestratable_message?(wa_message)

    # Enqueue orchestration job (pass object, GlobalID handles serialization)
    Whatsapp::OrchestrateTurnJob.perform_later(wa_message)

    Rails.logger.info({
      at: "process_message.orchestration_triggered",
      wa_message_id: wa_message.id,
      provider_message_id: wa_message.provider_message_id,
      message_type: wa_message.type_name
    }.to_json)
  rescue => e
    # Don't fail the message processing if orchestration fails
    Rails.logger.error({
      at: "process_message.orchestration_trigger_failed",
      wa_message_id: wa_message.id,
      error: e.class.name,
      message: e.message
    }.to_json)
  end

  # Determine if message type should be orchestrated
  def orchestratable_message?(wa_message)
    # Phase 1: Only text and button messages
    # Phase 2+: Expand to audio (with transcription), location, etc.
    %w[text button].include?(wa_message.type_name)
  end

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
