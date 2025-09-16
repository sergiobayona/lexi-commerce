require 'rails_helper'

# Manually load the MediaAPI module to fix autoloading issue
require Rails.root.join('app/services/whatsapp/media_api')

RSpec.describe Media::DownloadJob, type: :job do
  let(:bucket) { 'test-bucket' }
  let(:media_id) { 'abc123' }
  let(:sha256) { 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' }
  let(:mime_type) { 'audio/ogg' }
  let(:ext) { '.ogg' }
  let(:media_url) { 'https://graph.facebook.com/v21.0/media/abc123?token=shortlived' }

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

      allow(Whatsapp::MediaApi).to receive(:lookup)
        .with(media.provider_media_id)
        .and_return([ media_url, 'voice-message.ogg', mime_type, 2048 ])
      allow(Whatsapp::MediaApi).to receive(:extension_for)
        .with(mime_type).and_return(ext)
      # In production this returns a hash; the job expects an integer. Stub as integer.
      allow(Whatsapp::MediaApi).to receive(:stream_to_s3)
        .with(media_url, "wa/#{sha256}#{ext}")
        .and_return(3210)

      described_class.perform_now(media.id)

      media.reload
      expect(media.download_status).to eq('downloaded')
      expect(media.storage_url).to eq("s3://#{bucket}/wa/#{sha256}#{ext}")
      expect(media.bytes).to eq(3210)
      expect(media.mime_type).to eq(mime_type)
    end

    it 'no-ops when media already downloaded' do
      media = WaMedia.create!(
        provider_media_id: media_id,
        sha256: sha256,
        mime_type: mime_type,
        download_status: 'downloaded'
      )

      expect(Whatsapp::MediaApi).not_to receive(:lookup)

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

      allow(Whatsapp::MediaApi).to receive(:lookup)
        .and_return([ media_url, nil, mime_type, nil ])
      allow(Whatsapp::MediaApi).to receive(:extension_for)
        .and_return(ext)
      allow(Whatsapp::MediaApi).to receive(:stream_to_s3)
        .and_raise(StandardError.new('s3 upload failed'))

      expect { described_class.perform_now(media.id) }
        .to raise_error(StandardError, /s3 upload failed/)

      media.reload
      expect(media.download_status).to eq('failed')
      expect(media.last_error).to include('s3 upload failed')
    end
  end
end
