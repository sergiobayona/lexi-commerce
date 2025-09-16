module Whatsapp
  module Processors
    class AudioProcessor < BaseProcessor
      def call
        number  = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)
        msg = upsert_message!(common_message_attrs(number, contact).merge(
          type_name: "audio",
          has_media: true,
          media_kind: "audio"
        ))
        media = upsert_media!(
          provider_media_id: @msg.dig("audio", "id"),
          sha256:            @msg.dig("audio", "sha256"),
          mime_type:         @msg.dig("audio", "mime_type"),
          is_voice:          !!@msg.dig("audio", "voice")
        )
        msg.update!(media:) # if you chose the simple FK design
        if (ref = @msg["referral"]).present?
          WaReferral.upsert({
            message_id: msg.id,
            source_url: ref["source_url"], source_id: ref["source_id"], source_type: ref["source_type"],
            body: ref["body"], headline: ref["headline"], media_type: ref["media_type"],
            image_url: ref["image_url"], video_url: ref["video_url"], thumbnail_url: ref["thumbnail_url"],
            ctwa_clid: ref["ctwa_clid"],
            welcome_message_json: ref["welcome_message"] || {}
          }, unique_by: :index_wa_referrals_on_message_id)
        end
        Media::DownloadJob.perform_later(media.id)
      end
    end
  end
end
