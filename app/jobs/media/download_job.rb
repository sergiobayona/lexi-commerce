class Media::DownloadJob < ApplicationJob
  queue_as :media

  def perform(media_id)
    media = WaMedia.find(media_id)
    return if media.download_status_downloaded?

    media.update!(download_status: "downloading")

    # Use the convenient method that handles retries for expired URLs
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
  rescue => e
    Rails.logger.error("Failed to download media #{media_id}: #{e.class} - #{e.message}")
    media.update!(download_status: "failed", last_error: e.message[0..1000]) rescue nil
    raise
  end
end
