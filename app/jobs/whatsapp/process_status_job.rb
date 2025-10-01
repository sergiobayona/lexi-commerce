class Whatsapp::ProcessStatusJob < ApplicationJob
  queue_as :default

  def perform(value, status, webhook_event_id = nil)
    webhook_event = webhook_event_id ? WebhookEvent.find_by(id: webhook_event_id) : nil

    # Check for status-level errors
    if status["errors"].present?
      Whatsapp::Processors::ErrorProcessor.process_status_error(status, webhook_event)
      return
    end

    # Find the message this status update is for
    wa_message = WaMessage.find_by(provider_message_id: status["id"])

    unless wa_message
      Rails.logger.warn({
        at: "process_status.message_not_found",
        provider_message_id: status["id"],
        status_type: status["status"]
      }.to_json)
      return
    end

    # Create status event record
    WaMessageStatusEvent.create!(
      provider_message_id: status["id"],
      event_type: status["status"],
      event_timestamp: Time.at(status["timestamp"].to_i).utc,
      raw: status
    )

    # Update message status
    update_message_status(wa_message, status)

    Rails.logger.info({
      at: "process_status.updated",
      provider_message_id: status["id"],
      status: status["status"],
      wa_message_id: wa_message.id
    }.to_json)
  rescue => e
    Rails.logger.error({
      at: "process_status.error",
      error: e.class.name,
      message: e.message,
      provider_message_id: status["id"]
    }.to_json)
  end

  private

  def update_message_status(wa_message, status)
    # Map WhatsApp status to our message status
    case status["status"]
    when "sent"
      wa_message.update!(status: "sent")
    when "delivered"
      wa_message.update!(status: "delivered")
    when "read"
      wa_message.update!(status: "read")
    when "failed"
      wa_message.update!(status: "failed")
    end
  end
end
