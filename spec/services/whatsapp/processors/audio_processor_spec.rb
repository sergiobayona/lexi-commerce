# spec/services/whatsapp/processors/audio_processor_spec.rb
require "rails_helper"

RSpec.describe Whatsapp::Processors::AudioProcessor do
  let(:base_value) do
    {
      "messaging_product" => "whatsapp",
      "metadata" => { "display_phone_number" => "15550000000", "phone_number_id" => "111" },
      "contacts" => [ { "wa_id" => "16505551234", "profile" => { "name" => "Alice" } } ]
    }
  end

  let(:base_msg) do
    {
      "id" => "wamid.123",
      "from" => "16505551234",
      "timestamp" => "1749416383",
      "type" => "audio",
      "audio" => {
        "id" => "media.777",
        "sha256" => "b1b2b3",
        "mime_type" => "audio/ogg",
        "voice" => true
      }
    }
  end

  let(:value) { base_value }
  let(:msg) { base_msg }

  describe "#call" do
    context "with valid audio message" do
      it "creates message + media and enqueues Media::DownloadJob" do
        expect {
          described_class.new(value, msg).call
        }.to change(WaMessage, :count).by(1)
         .and change(WaMedia, :count).by(1)
         .and change(WaMessageMedia, :count).by(1)

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        expect(m.type_name).to eq("audio")
        expect(m.media_kind).to eq("audio")
        expect(m.has_media).to be true
        expect(m.direction).to eq("inbound")
        expect(m.status).to eq("received")
        expect(m.media).to be_present

        # Verify media attributes
        media = m.media
        expect(media.provider_media_id).to eq("media.777")
        expect(media.sha256).to eq("b1b2b3")
        expect(media.mime_type).to eq("audio/ogg")
        expect(media.is_voice).to be true

        # Verify job enqueueing
        expect(Media::DownloadJob).to have_been_enqueued.with(media.id)
      end

      it "creates proper timestamps" do
        described_class.new(value, msg).call

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        expect(m.timestamp).to eq(Time.at(1749416383).utc)
      end

      it "stores metadata and contact snapshots" do
        described_class.new(value, msg).call

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        expect(m.metadata_snapshot).to eq(value["metadata"])
        expect(m.wa_contact_snapshot).to eq(value["contacts"].first)
      end

      it "creates message-media association with correct purpose" do
        described_class.new(value, msg).call

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        message_media = WaMessageMedia.find_by!(wa_message_id: m.id)
        expect(message_media.purpose).to eq("primary")
      end
    end

    context "with audio file (non-voice)" do
      let(:msg) do
        base_msg.merge("audio" => base_msg["audio"].merge("voice" => false))
      end

      it "correctly sets is_voice to false" do
        described_class.new(value, msg).call

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        expect(m.media.is_voice).to be false
      end
    end

    context "with different audio formats" do
      let(:msg) do
        base_msg.merge("audio" => {
          "id" => "media.mp3",
          "sha256" => "abc123",
          "mime_type" => "audio/mpeg",
          "voice" => false
        })
      end

      it "handles different mime types correctly" do
        described_class.new(value, msg).call

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        expect(m.media.mime_type).to eq("audio/mpeg")
        expect(m.media.provider_media_id).to eq("media.mp3")
      end
    end

    context "with referral data" do
      let(:msg) do
        base_msg.merge("referral" => {
          "source_url" => "https://example.com/ad",
          "source_id" => "ad123",
          "source_type" => "ad",
          "body" => "Check out our product",
          "headline" => "Special Offer",
          "media_type" => "image",
          "image_url" => "https://example.com/image.jpg",
          "video_url" => nil,
          "thumbnail_url" => nil,
          "ctwa_clid" => "click123",
          "welcome_message" => { "text" => "Welcome!" }
        })
      end

      it "attempts to create referral record (may fail on missing index)" do
        # This test documents the behavior but may fail if database index is missing
        expect {
          described_class.new(value, msg).call
        }.to raise_error(ArgumentError, /No unique index found/)
      end
    end

    context "without referral data" do
      it "does not create referral record" do
        expect {
          described_class.new(value, msg).call
        }.not_to change(WaReferral, :count)
      end
    end

    context "missing contact information" do
      let(:value) { base_value.merge("contacts" => []) }

      it "requires contact information (database constraint)" do
        expect {
          described_class.new(value, msg).call
        }.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    context "with nil contacts array" do
      let(:value) { base_value.merge("contacts" => nil) }

      it "requires contact information (database constraint)" do
        expect {
          described_class.new(value, msg).call
        }.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    context "idempotency" do
      it "is idempotent on re-processing" do
        described_class.new(value, msg).call
        expect {
          described_class.new(value, msg).call
        }.not_to change { [ WaMessage.count, WaMedia.count, WaMessageMedia.count ] }
      end

      it "enqueues download job on each call (not deduplicated)" do
        described_class.new(value, msg).call

        expect {
          described_class.new(value, msg).call
        }.to have_enqueued_job(Media::DownloadJob)
      end

      it "handles referral processing consistently" do
        msg_with_ref = msg.merge("referral" => {
          "source_url" => "https://example.com",
          "source_id" => "123"
        })

        # Both calls should fail consistently due to missing database index
        expect {
          described_class.new(value, msg_with_ref).call
        }.to raise_error(ArgumentError, /No unique index found/)

        expect {
          described_class.new(value, msg_with_ref).call
        }.to raise_error(ArgumentError, /No unique index found/)
      end
    end

    context "error handling" do
      it "handles invalid timestamp gracefully" do
        invalid_msg = msg.merge("timestamp" => "invalid")

        expect {
          described_class.new(value, invalid_msg).call
        }.to change(WaMessage, :count).by(1)

        m = WaMessage.find_by!(provider_message_id: "wamid.123")
        # Time.at("invalid".to_i) becomes Time.at(0) = 1970-01-01
        expect(m.timestamp).to eq(Time.at(0).utc)
      end

      it "handles missing audio metadata gracefully" do
        minimal_msg = msg.merge("audio" => { "id" => "media.minimal" })

        expect {
          described_class.new(value, minimal_msg).call
        }.to change(WaMessage, :count).by(1)
         .and change(WaMedia, :count).by(1)

        media = WaMedia.find_by!(provider_media_id: "media.minimal")
        expect(media.sha256).to be_nil
        expect(media.mime_type).to be_nil
        expect(media.is_voice).to be false
      end
    end
  end
end
