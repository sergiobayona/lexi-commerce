module Whatsapp
  module Processors
    class ButtonProcessor < BaseProcessor
      def call
        number = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)

        # Extract button data
        button_data = @msg["button"] || {}

        msg_rec = upsert_message!(
          provider_message_id: @msg["id"],
          direction: "inbound",
          wa_contact_id: contact&.id,
          wa_business_number_id: number.id,
          type_name: "button",
          has_media: false,
          body_text: button_data["text"],
          timestamp: Time.at(@msg["timestamp"].to_i).utc,
          status: "received",
          metadata_snapshot: @value["metadata"],
          wa_contact_snapshot: (@value["contacts"]&.first || {}),
          raw: @msg
        )

        # Store button payload and context if present
        if button_data.present? || @msg["context"].present?
          msg_rec.update!(
            raw: @msg.merge({
              button_payload: button_data["payload"],
              button_text: button_data["text"],
              context_message_id: @msg.dig("context", "id"),
              context_from: @msg.dig("context", "from")
            })
          )
        end

        msg_rec
      end
    end
  end
end
