class Media::DownloadJob < ApplicationJob
  queue_as :media

  def perform(media_id)
    media = WaMedia.find(media_id)
    return if media.download_status_downloaded?

    media.update!(download_status: "downloading")

    # 1) Get media URL from Graph API: GET /{media_id}?access_token=...
    media_url, filename, mime_type, file_size = Whatsapp::MediaAPI.lookup(media.provider_media_id)

    # 2) Stream download and upload to S3 with sha256-based key
    key = "wa/#{media.sha256}#{Whatsapp::MediaAPI.extension_for(mime_type)}"
    bytes = Whatsapp::MediaAPI.stream_to_s3(media_url, key)

    media.update!(
      storage_url: "s3://#{ENV["S3_BUCKET"]}/#{key}",
      bytes: bytes,
      mime_type: mime_type.presence || media.mime_type,
      download_status: "downloaded"
    )
  rescue => e
    media.update!(download_status: "failed", last_error: e.message[0..1000]) rescue nil
    raise
  end
end
