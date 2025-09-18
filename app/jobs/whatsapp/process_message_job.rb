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
    handler_result = Whatsapp::Intent::Handler.new(value: value, msg: msg).call

    # If this is an audio message and no welcome message was sent,
    # emit outbox event for speech processing
    if type == "audio" && !handler_result.dig(:actions, :welcome_message_sent)
      emit_audio_received_event(msg["id"], value)
    end
  rescue => e
    Rails.logger.error({ at: "process_message.error", error: e.class.name, message: e.message }.to_json)
  end

  private

  def emit_audio_received_event(provider_message_id, value)
    wa_message = WaMessage.find_by(provider_message_id: provider_message_id)
    return unless wa_message

    wa_contact = wa_message.wa_contact
    wa_business_number = wa_message.wa_business_number
    wa_media = wa_message.wa_media.first

    return unless wa_contact && wa_business_number && wa_media

    Outbox::Dispatcher.new.dispatch_audio_received_event(
      wa_message: wa_message,
      wa_contact: wa_contact,
      wa_media: wa_media,
      business_number: wa_business_number
    )
  rescue => e
    Rails.logger.error({
      at: "process_message.emit_audio_event_error",
      provider_message_id: provider_message_id,
      error: e.class.name,
      message: e.message
    }.to_json)
  end
end
