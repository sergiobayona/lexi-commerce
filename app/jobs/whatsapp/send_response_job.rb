# frozen_string_literal: true

module Whatsapp
  # Sends WhatsApp message responses asynchronously
  # Handles sending agent responses back to the user via WhatsApp Business API
  class SendResponseJob < ApplicationJob
    include Whatsapp::Responders::BaseResponder

    queue_as :high_priority

    # @param wa_message [WaMessage] The original incoming message
    # @param messages [Array<Hash>] Array of message hashes to send (e.g., [{type: 'text', text: 'Hello'}])
    def perform(wa_message:, messages:)
      return if messages.blank?

      Rails.logger.info({
        at: "send_response.start",
        wa_message_id: wa_message.id,
        provider_message_id: wa_message.provider_message_id,
        message_count: messages.size
      }.to_json)

      messages.each do |message|
        send_message(wa_message, message)
      end

      Rails.logger.info({
        at: "send_response.complete",
        wa_message_id: wa_message.id,
        provider_message_id: wa_message.provider_message_id,
        messages_sent: messages.size
      }.to_json)

    rescue => e
      Rails.logger.error({
        at: "send_response.error",
        wa_message_id: wa_message&.id,
        provider_message_id: wa_message&.provider_message_id,
        error_class: e.class.name,
        error_message: e.message,
        backtrace: e.backtrace.first(5)
      }.to_json)
      raise # Re-raise for job retry mechanism
    end

    private

    def send_message(wa_message, message)
      case message[:type]&.to_sym
      when :text
        # Extract text body from nested structure: {type: "text", text: {body: "..."}}
        text_body = message.dig(:text, :body)
        send_text_message(wa_message, text_body)
      when :interactive
        # Handle interactive messages (buttons, lists) - placeholder for future
        Rails.logger.info({
          at: "send_response.interactive_message",
          interactive_type: message.dig(:interactive, :type),
          wa_message_id: wa_message.id
        }.to_json)
        # TODO: Implement interactive message sending
      else
        Rails.logger.warn({
          at: "send_response.unsupported_type",
          type: message[:type],
          wa_message_id: wa_message.id
        }.to_json)
      end
    end

    def send_text_message(wa_message, text)
      return if text.blank?

      # Send via WhatsApp API
      response = send_text!(
        to: wa_message.wa_contact.wa_id,
        body: text,
        business_number: wa_message.wa_business_number,
        preview_url: false
      )

      # Record outbound message for auditing
      provider_message_id = response.dig("messages", 0, "id")
      if provider_message_id
        record_outbound_message!(
          wa_contact: wa_message.wa_contact,
          wa_business_number: wa_message.wa_business_number,
          body: text,
          provider_message_id: provider_message_id,
          raw: response
        )
      end

      Rails.logger.info({
        at: "send_response.message_sent",
        wa_message_id: wa_message.id,
        outbound_message_id: provider_message_id,
        text_length: text.length
      }.to_json)

    rescue Whatsapp::Responders::BaseResponder::ApiError => e
      Rails.logger.error({
        at: "send_response.api_error",
        wa_message_id: wa_message.id,
        error_status: e.status,
        error_code: e.code,
        error_message: e.message
      }.to_json)
      raise
    end
  end
end
