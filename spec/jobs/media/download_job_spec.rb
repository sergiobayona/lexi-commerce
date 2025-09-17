require 'rails_helper'

# Manually load the MediaAPI module to fix autoloading issue
require Rails.root.join('app/services/whatsapp/media_api')

RSpec.describe Media::DownloadJob, type: :job do
  let(:bucket) { 'test-bucket' }
  let(:media_id) { 'abc123' }
  let(:sha256) { 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' }
  let(:mime_type) { 'audio/ogg' }
  let(:ext) { '.ogg' }
  let(:media_url) { 'https://graph.facebook.com/v23.0/media/abc123?token=shortlived' }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('S3_BUCKET').and_return(bucket)
  end

  describe '#perform' do
    it 'downloads media, uploads to S3, and updates the record' do
      media = WaMedia.create!(
        provider_media_id: media_id,
        sha256: sha256,
        mime_type: '',
        download_status: 'pending'
      )

      # Mock the new download_to_s3_by_media_id method
      expected_result = {
        key: "wa/#{media_id}#{ext}",
        bytes: 3210,
        sha256: sha256,
        mime_type: mime_type,
        filename: 'voice-message.ogg'
      }

      allow(Whatsapp::MediaApi).to receive(:download_to_s3_by_media_id)
        .with(media.provider_media_id, key_prefix: 'wa/')
        .and_return(expected_result)

      described_class.perform_now(media.id)

      media.reload
      expect(media.download_status).to eq('downloaded')
      expect(media.storage_url).to eq("s3://#{bucket}/wa/#{media_id}#{ext}")
      expect(media.bytes).to eq(3210)
      expect(media.sha256).to eq(sha256)
      expect(media.mime_type).to eq(mime_type)
    end

    it 'no-ops when media already downloaded' do
      media = WaMedia.create!(
        provider_media_id: media_id,
        sha256: sha256,
        mime_type: mime_type,
        download_status: 'downloaded'
      )

      expect(Whatsapp::MediaApi).not_to receive(:download_to_s3_by_media_id)

      described_class.perform_now(media.id)

      expect(media.reload.download_status).to eq('downloaded')
    end

    it 'marks failed and re-raises on error' do
      media = WaMedia.create!(
        provider_media_id: media_id,
        sha256: sha256,
        mime_type: '',
        download_status: 'pending'
      )

      allow(Whatsapp::MediaApi).to receive(:download_to_s3_by_media_id)
        .with(media.provider_media_id, key_prefix: 'wa/')
        .and_raise(StandardError.new('s3 upload failed'))

      expect { described_class.perform_now(media.id) }
        .to raise_error(StandardError, /s3 upload failed/)

      media.reload
      expect(media.download_status).to eq('failed')
      expect(media.last_error).to include('s3 upload failed')
    end
  end
end
