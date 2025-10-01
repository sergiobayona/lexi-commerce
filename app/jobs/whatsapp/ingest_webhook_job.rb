class Whatsapp::IngestWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload, webhook_event_id = nil)
    webhook_event = webhook_event_id ? WebhookEvent.find_by(id: webhook_event_id) : nil

    Array(payload["entry"]).each do |entry|
      Array(entry["changes"]).each do |change|
        value = change["value"] || {}
        next unless value["messaging_product"] == "whatsapp"

        # Process system/app/account-level errors
        if value["errors"].present?
          Whatsapp::Processors::ErrorProcessor.new(value: value, webhook_event: webhook_event).call
        end

        # Process messages
        Array(value["messages"]).to_a.each do |msg|
          Whatsapp::ProcessMessageJob.perform_later(value, msg, webhook_event&.id)
        end

        # Process message status updates (delivery/read receipts)
        Array(value["statuses"]).to_a.each do |status|
          Whatsapp::ProcessStatusJob.perform_later(value, status, webhook_event&.id)
        end
      end
    end
  end
end
