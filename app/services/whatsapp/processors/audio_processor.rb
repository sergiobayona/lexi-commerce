        require "whisper"
module Whatsapp
  module Processors
    class AudioProcessor < BaseProcessor
      def call
        number = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)

        msg_rec = upsert_message!(
          provider_message_id: @msg["id"],
          direction: "inbound",
          wa_contact_id: contact&.id,
          wa_business_number_id: number.id,
          type_name: "audio",
          has_media: true,
          media_kind: "audio",
          timestamp: Time.at(@msg["timestamp"].to_i).utc,
          status: "received",
          metadata_snapshot: @value["metadata"],
          wa_contact_snapshot: (@value["contacts"]&.first || {}),
          raw: @msg
        )

        media = upsert_media!(
          provider_media_id: @msg.dig("audio", "id"),
          sha256:            @msg.dig("audio", "sha256"),
          mime_type:         @msg.dig("audio", "mime_type"),
          is_voice:          !!@msg.dig("audio", "voice")
        )

        WaMessageMedia.find_or_create_by!(wa_message_id: msg_rec.id, wa_media_id: media.id) do |mm|
          mm.purpose = "primary"
        end

        if (ref = @msg["referral"]).present?
          WaReferral.upsert({
            wa_message_id: msg_rec.id,
            source_url: ref["source_url"], source_id: ref["source_id"], source_type: ref["source_type"],
            body: ref["body"], headline: ref["headline"], media_type: ref["media_type"],
            image_url: ref["image_url"], video_url: ref["video_url"], thumbnail_url: ref["thumbnail_url"],
            ctwa_clid: ref["ctwa_clid"],
            welcome_message_json: ref["welcome_message"] || {}
          }, unique_by: :index_wa_referrals_on_wa_message_id)
        end

        file_path = Media::Downloader.call(media.id)

        # Convert OGG to WAV format for Whisper transcription
        wav_path = Media::AudioConverter.to_wav(file_path)

        whisper = Whisper::Context.new("base")

        params = Whisper::Params.new(
          translate: false,
          print_timestamps: false
        )

        @transcription = ""

        whisper.transcribe(wav_path, params) do |whole_text|
          @transcription = whole_text
        end

        msg_rec.update!(body_text: @transcription)
        msg_rec.body_text
      end
    end
  end
end
