module Media
  class Downloader
    def self.call(media_id)
      new(media_id).call
    end

    def initialize(media_id)
      @media_id = media_id
    end

    def call
      media = WaMedia.find(@media_id)
      return if media.download_status_downloaded?

      media.update!(download_status: "downloading")

      file_path = if Rails.env.development?
        download_to_local(media)
      else
        download_to_s3(media)
      end

      file_path
    rescue => e
      Rails.logger.error("Failed to download media #{@media_id}: #{e.class} - #{e.message}")
      media.update!(download_status: "failed", last_error: e.message[0..1000]) rescue nil
      raise
    end

    private

    attr_reader :media_id

    def download_to_local(media)
      result = Whatsapp::MediaApi.download_to_local_by_media_id(
        media.provider_media_id
      )

      media.update!(
        storage_url: "file://#{result[:path]}",
        bytes: result[:bytes],
        sha256: result[:sha256],
        mime_type: result[:mime_type].presence || media.mime_type,
        download_status: "downloaded"
      )

      Rails.logger.info("Successfully downloaded media #{media.provider_media_id} to local file: #{result[:path]}")
      result[:path]
    end

    def download_to_s3(media)
      result = Whatsapp::MediaApi.download_to_s3_by_media_id(
        media.provider_media_id,
        key_prefix: "wa/"
      )

      media.update!(
        storage_url: "s3://#{ENV["S3_BUCKET"]}/#{result[:key]}",
        bytes: result[:bytes],
        sha256: result[:sha256],
        mime_type: result[:mime_type].presence || media.mime_type,
        download_status: "downloaded"
      )

      Rails.logger.info("Successfully downloaded media #{media.provider_media_id} to S3: #{result[:key]}")
      result[:key]
    end
  end
end
