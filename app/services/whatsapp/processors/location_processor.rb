module Whatsapp
  module Processors
    class LocationProcessor < BaseProcessor
      def call
        number = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)

        # Extract location data
        location_data = @msg["location"] || {}

        # Build body_text from location information for searchability
        body_text_parts = []
        body_text_parts << location_data["name"] if location_data["name"].present?
        body_text_parts << location_data["address"] if location_data["address"].present?
        body_text = body_text_parts.join(" - ")

        msg_rec = upsert_message!(
          provider_message_id: @msg["id"],
          direction: "inbound",
          wa_contact_id: contact&.id,
          wa_business_number_id: number.id,
          type_name: "location",
          has_media: false,
          body_text: body_text.presence,
          timestamp: Time.at(@msg["timestamp"].to_i).utc,
          status: "received",
          metadata_snapshot: @value["metadata"],
          wa_contact_snapshot: (@value["contacts"]&.first || {}),
          raw: @msg
        )

        # Store detailed location data in raw field
        if location_data.present?
          msg_rec.update!(
            raw: @msg.merge({
              location_details: {
                latitude: location_data["latitude"],
                longitude: location_data["longitude"],
                name: location_data["name"],
                address: location_data["address"],
                url: location_data["url"]
              }.compact
            })
          )
        end

        msg_rec.body_text
      end
    end
  end
end
