# frozen_string_literal: true

module Outbox
  class ProcessEventJob < ApplicationJob
    queue_as :outbox
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(outbox_event_id)
      outbox_event = OutboxEvent.find(outbox_event_id)

      return if outbox_event.processed?

      # Mark as processing to prevent concurrent execution
      outbox_event.mark_processing!

      # Dispatch to Redis stream
      dispatcher = Outbox::Dispatcher.new
      case outbox_event.event_type
      when "audio_received"
        process_audio_received_event(outbox_event, dispatcher)
      else
        raise "Unknown event type: #{outbox_event.event_type}"
      end

      # Mark as processed
      outbox_event.mark_processed!

      Rails.logger.info({
        at: "outbox.process_event.completed",
        outbox_event_id: outbox_event.id,
        event_type: outbox_event.event_type
      }.to_json)
    rescue StandardError => e
      handle_processing_error(outbox_event, e)
      raise
    end

    private

    def process_audio_received_event(outbox_event, dispatcher)
      # Extract IDs from stored payload
      payload = outbox_event.payload.with_indifferent_access
      wa_message = WaMessage.find(payload[:wa_message_id])
      wa_contact = WaContact.find(payload[:wa_contact_id])
      wa_media = WaMedia.find_by(provider_media_id: payload.dig(:media, :provider_media_id))
      business_number = WaBusinessNumber.find(payload[:business_number_id])

      raise "Missing required records for audio_received event" unless wa_message && wa_contact && wa_media && business_number

      # Use the dispatcher to publish (will handle idempotency)
      stream_publisher = Redis::StreamPublisher.new
      stream_publisher.publish(
        payload,
        idempotency_key: outbox_event.idempotency_key
      )
    end

    def handle_processing_error(outbox_event, error)
      if outbox_event&.persisted?
        outbox_event.mark_failed!(error.message)
      end

      Rails.logger.error({
        at: "outbox.process_event.error",
        outbox_event_id: outbox_event&.id,
        error: error.class.name,
        message: error.message
      }.to_json)
    end
  end
end