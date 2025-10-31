module Whatsapp
  module Processors
    class ContactProcessor < BaseProcessor
      def call
        number = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)

        # Extract contacts data (WhatsApp contact cards sent by user)
        contacts_data = @msg["contacts"] || []

        # Build body text from contact names for searchability
        body_text = contacts_data.map do |contact_card|
          contact_card.dig("name", "formatted_name") ||
          [ contact_card.dig("name", "first_name"), contact_card.dig("name", "last_name") ].compact.join(" ")
        end.compact.join(", ")

        msg_rec = upsert_message!(
          provider_message_id: @msg["id"],
          direction: "inbound",
          wa_contact_id: contact&.id,
          wa_business_number_id: number.id,
          type_name: "contacts",
          has_media: false,
          body_text: body_text,
          timestamp: Time.at(@msg["timestamp"].to_i).utc,
          status: "received",
          metadata_snapshot: @value["metadata"],
          wa_contact_snapshot: (@value["contacts"]&.first || {}),
          raw: @msg
        )

        # Store detailed contact card information in raw field
        if contacts_data.present?
          msg_rec.update!(
            raw: @msg.merge({
              shared_contacts: contacts_data.map do |contact_card|
                {
                  name: contact_card["name"],
                  org: contact_card["org"],
                  phones: contact_card["phones"],
                  emails: contact_card["emails"],
                  urls: contact_card["urls"],
                  addresses: contact_card["addresses"],
                  birthday: contact_card["birthday"]
                }.compact
              end
            })
          )
        end

        msg_rec
      end
    end
  end
end
