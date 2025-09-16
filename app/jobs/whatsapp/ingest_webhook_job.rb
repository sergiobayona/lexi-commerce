class Whatsapp::IngestWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload)
    Array(payload["entry"]).each do |entry|
      Array(entry["changes"]).each do |change|
        value = change["value"] || {}
        next unless value["messaging_product"] == "whatsapp"

        Array(value["messages"]).to_a.each do |msg|
          Whatsapp::ProcessMessageJob.perform_later(value, msg)
        end

        # (Optional) handle value["statuses"] for delivery/read receipts here
      end
    end
  end
end
