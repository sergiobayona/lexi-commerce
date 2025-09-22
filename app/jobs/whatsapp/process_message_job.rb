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

  private

  def user_was_prompted_for_practice?(contact)
    return false unless contact

    WaMessage
      .where(wa_contact_id: contact.id, direction: "outbound")
      .where("body_text ILIKE ?", "%practice%")
      .exists?
  end

  def emit_audio_received_event(provider_message_id, value)
    wa_message = WaMessage.find_by(provider_message_id: provider_message_id)
    return unless wa_message

    wa_contact = wa_message.wa_contact
    wa_business_number = wa_message.wa_business_number
    wa_media = wa_message.wa_media

    return unless wa_contact && wa_business_number && wa_media

    # Build payload and publish directly
    payload = {
      provider: "whatsapp",
      provider_message_id: wa_message.provider_message_id,
      wa_message_id: wa_message.id,
      wa_contact_id: wa_contact.id,
      user_e164: wa_contact.wa_id,
      media: {
        provider_media_id: wa_media.provider_media_id,
        sha256: wa_media.sha256,
        mime_type: wa_media.mime_type,
        bytes: wa_media.bytes,
        storage_url: wa_media.storage_url
      },
      business_number_id: wa_business_number.id,
      timestamp: wa_message.timestamp.iso8601
    }

    idempotency_key = "audio_received:#{provider_message_id}"
    Stream::Publisher.new.publish(payload, idempotency_key: idempotency_key)

    Rails.logger.info({
      at: "audio_received.dispatched",
      provider_message_id: provider_message_id
    }.to_json)
  rescue => e
    Rails.logger.error({
      at: "process_message.emit_audio_event_error",
      provider_message_id: provider_message_id,
      error: e.class.name,
      message: e.message
    }.to_json)
  end
end
