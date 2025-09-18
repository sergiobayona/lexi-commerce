# frozen_string_literal: true

module Outbox
  class Dispatcher
    include ActiveSupport::Benchmarkable

    class DispatchError < StandardError; end

    def initialize(stream_publisher: nil)
      @stream_publisher = stream_publisher || Redis::StreamPublisher.new
    end

    def dispatch_audio_received_event(wa_message:, wa_contact:, wa_media:, business_number:)
      benchmark "Outbox event dispatch", level: :info do
        # Create outbox event record for audit trail
        outbox_event = create_outbox_event(wa_message, wa_contact, wa_media, business_number)

        # Publish to Redis stream
        publish_to_stream(outbox_event)

        # Mark as processed
        outbox_event.mark_processed!

        Rails.logger.info({
          at: "outbox.audio_received.dispatched",
          outbox_event_id: outbox_event.id,
          wa_message_id: wa_message.id,
          idempotency_key: outbox_event.idempotency_key
        }.to_json)

        outbox_event
      end
    rescue StandardError => e
      handle_dispatch_error(outbox_event, e)
      raise DispatchError, "Failed to dispatch audio_received event: #{e.message}"
    end

    private

    def create_outbox_event(wa_message, wa_contact, wa_media, business_number)
      payload = build_audio_received_payload(wa_message, wa_contact, wa_media, business_number)
      idempotency_key = "audio_received:#{wa_message.provider_message_id}"

      OutboxEvent.create!(
        event_type: "audio_received",
        payload: payload,
        idempotency_key: idempotency_key,
        status: "processing"
      )
    rescue ActiveRecord::RecordNotUnique
      # Event already exists, return existing record
      Rails.logger.info({
        at: "outbox.audio_received.duplicate_event",
        provider_message_id: wa_message.provider_message_id
      }.to_json)
      OutboxEvent.find_by!(idempotency_key: "audio_received:#{wa_message.provider_message_id}")
    end

    def build_audio_received_payload(wa_message, wa_contact, wa_media, business_number)
      {
        provider: "whatsapp",
        provider_message_id: wa_message.provider_message_id,
        wa_message_id: wa_message.id,
        wa_contact_id: wa_contact.id,
        user_e164: wa_contact.wa_id,
        media: {
          provider_media_id: wa_media.provider_media_id,
          sha256: wa_media.sha256,
          mime_type: wa_media.mime_type,
          bytes: wa_media.bytes
        },
        business_number_id: business_number.id,
        timestamp: wa_message.timestamp.iso8601
      }
    end

    def publish_to_stream(outbox_event)
      @stream_publisher.publish(
        outbox_event.payload,
        idempotency_key: outbox_event.idempotency_key
      )
    end

    def handle_dispatch_error(outbox_event, error)
      if outbox_event&.persisted?
        outbox_event.mark_failed!(error.message)
      end

      Rails.logger.error({
        at: "outbox.dispatch_error",
        error: error.class.name,
        message: error.message,
        outbox_event_id: outbox_event&.id
      }.to_json)
    end

    def logger
      Rails.logger
    end
  end
end