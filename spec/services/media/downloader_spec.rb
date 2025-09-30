# spec/services/media/downloader_spec.rb
require "rails_helper"

RSpec.describe Media::Downloader do
  let(:media) { create(:wa_media, provider_media_id: "test-media-123", download_status: "pending") }

  describe ".call" do
    it "delegates to instance method" do
      expect_any_instance_of(described_class).to receive(:call)
      described_class.call(media.id)
    end
  end

  describe "#call" do
    context "when media is already downloaded" do
      let(:media) { create(:wa_media, download_status: "downloaded") }

      it "returns early without downloading" do
        expect(Whatsapp::MediaApi).not_to receive(:download_to_local_by_media_id)
        expect(Whatsapp::MediaApi).not_to receive(:download_to_s3_by_media_id)

        described_class.call(media.id)
      end
    end

    context "in development environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      it "downloads to local filesystem" do
        result = {
          path: "/tmp/test-media-123.ogg",
          bytes: 1024,
          sha256: "abc123",
          mime_type: "audio/ogg"
        }

        expect(Whatsapp::MediaApi).to receive(:download_to_local_by_media_id)
          .with("test-media-123")
          .and_return(result)

        file_path = described_class.call(media.id)

        media.reload
        expect(media.download_status).to eq("downloaded")
        expect(media.storage_url).to eq("file:///tmp/test-media-123.ogg")
        expect(media.bytes).to eq(1024)
        expect(media.sha256).to eq("abc123")
        expect(media.mime_type).to eq("audio/ogg")
        expect(file_path).to eq("/tmp/test-media-123.ogg")
      end

      it "sets download status to downloading before starting" do
        result = {
          path: "/tmp/test.ogg",
          bytes: 1024,
          sha256: "abc123",
          mime_type: "audio/ogg"
        }

        allow(Whatsapp::MediaApi).to receive(:download_to_local_by_media_id).and_return(result)

        expect {
          described_class.call(media.id)
        }.to change { media.reload.download_status }.from("pending").to("downloaded")
      end

      it "uses existing mime_type if download doesn't provide one" do
        media.update!(mime_type: "audio/mpeg")
        result = {
          path: "/tmp/test.ogg",
          bytes: 1024,
          sha256: "abc123",
          mime_type: nil
        }

        expect(Whatsapp::MediaApi).to receive(:download_to_local_by_media_id)
          .and_return(result)

        described_class.call(media.id)

        media.reload
        expect(media.mime_type).to eq("audio/mpeg")
      end
    end

    context "in production environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("S3_BUCKET").and_return("test-bucket")
      end

      it "downloads to S3" do
        result = {
          key: "wa/test-media-123.ogg",
          bytes: 1024,
          sha256: "abc123",
          mime_type: "audio/ogg"
        }

        expect(Whatsapp::MediaApi).to receive(:download_to_s3_by_media_id)
          .with("test-media-123", key_prefix: "wa/")
          .and_return(result)

        file_path = described_class.call(media.id)

        media.reload
        expect(media.download_status).to eq("downloaded")
        expect(media.storage_url).to eq("s3://test-bucket/wa/test-media-123.ogg")
        expect(media.bytes).to eq(1024)
        expect(media.sha256).to eq("abc123")
        expect(media.mime_type).to eq("audio/ogg")
        expect(file_path).to eq("wa/test-media-123.ogg")
      end

      it "uses existing mime_type if download doesn't provide one" do
        media.update!(mime_type: "audio/mpeg")
        result = {
          key: "wa/test.ogg",
          bytes: 1024,
          sha256: "abc123",
          mime_type: ""
        }

        allow(ENV).to receive(:[]).with("S3_BUCKET").and_return("test-bucket")
        expect(Whatsapp::MediaApi).to receive(:download_to_s3_by_media_id)
          .and_return(result)

        described_class.call(media.id)

        media.reload
        expect(media.mime_type).to eq("audio/mpeg")
      end
    end

    context "error handling" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      it "updates status to failed and records error message" do
        error_message = "Network timeout occurred"
        expect(Whatsapp::MediaApi).to receive(:download_to_local_by_media_id)
          .and_raise(StandardError.new(error_message))

        expect {
          described_class.call(media.id)
        }.to raise_error(StandardError)

        media.reload
        expect(media.download_status).to eq("failed")
        expect(media.last_error).to eq(error_message)
      end

      it "truncates error messages longer than 1000 characters" do
        long_error = "x" * 1500
        expect(Whatsapp::MediaApi).to receive(:download_to_local_by_media_id)
          .and_raise(StandardError.new(long_error))

        expect {
          described_class.call(media.id)
        }.to raise_error(StandardError)

        media.reload
        expect(media.last_error.length).to eq(1000)
      end

      it "handles failure to update status gracefully" do
        allow(Whatsapp::MediaApi).to receive(:download_to_local_by_media_id)
          .and_raise(StandardError.new("Download failed"))
        allow(media).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          described_class.call(media.id)
        }.to raise_error(StandardError, "Download failed")
      end
    end

    context "media not found" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          described_class.call(999999)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
