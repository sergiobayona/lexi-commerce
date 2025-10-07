module Whatsapp
  module Processors
    class DocumentProcessor < BaseProcessor
      def call
        number = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)

        # Extract document data
        document_data = @msg["document"] || {}

        msg_rec = upsert_message!(
          provider_message_id: @msg["id"],
          direction: "inbound",
          wa_contact_id: contact&.id,
          wa_business_number_id: number.id,
          type_name: "document",
          has_media: true,
          media_kind: "document",
          body_text: document_data["caption"],
          timestamp: Time.at(@msg["timestamp"].to_i).utc,
          status: "received",
          metadata_snapshot: @value["metadata"],
          wa_contact_snapshot: (@value["contacts"]&.first || {}),
          raw: @msg
        )

        # Create media record for the document
        media = upsert_media!(
          provider_media_id: document_data["id"],
          sha256: document_data["sha256"],
          mime_type: document_data["mime_type"],
          is_voice: false
        )

        # Link message to media
        WaMessageMedia.find_or_create_by!(wa_message_id: msg_rec.id, wa_media_id: media.id) do |mm|
          mm.purpose = "primary"
        end

        # Store filename in message raw field for reference
        if document_data["filename"].present?
          msg_rec.update!(
            raw: @msg.merge({ document_filename: document_data["filename"] })
          )
        end

        # Queue media download
        Media::Downloader.call(media.id)

        msg_rec
      end
    end
  end
end
