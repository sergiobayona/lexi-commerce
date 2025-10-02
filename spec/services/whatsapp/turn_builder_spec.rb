# frozen_string_literal: true

require "rails_helper"

RSpec.describe Whatsapp::TurnBuilder do
  let(:wa_contact) { create(:wa_contact, wa_id: "16505551234") }
  let(:wa_business_number) { create(:wa_business_number, phone_number_id: "106540352242922") }

  describe "#build" do
    context "with text message" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.test123",
          type_name: "text",
          body_text: "Hello, world!",
          timestamp: Time.zone.parse("2025-10-02 10:00:00 UTC")
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "builds turn with correct structure" do
        expect(turn).to include(
          tenant_id: wa_business_number.phone_number_id,
          wa_id: wa_contact.wa_id,
          message_id: "wamid.test123",
          text: "Hello, world!",
          payload: nil,
          timestamp: "2025-10-02T10:00:00Z"
        )
      end

      it "extracts text from body_text" do
        expect(turn[:text]).to eq("Hello, world!")
      end

      it "has nil payload for text messages" do
        expect(turn[:payload]).to be_nil
      end
    end

    context "with button message" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.button123",
          type_name: "button",
          body_text: "Ver ubicación",
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "extracts button text" do
        expect(turn[:text]).to eq("Ver ubicación")
      end

      it "includes payload for button messages" do
        # Currently returns nil, but structure is ready for enhancement
        expect(turn).to have_key(:payload)
      end
    end

    context "with audio message" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.audio123",
          type_name: "audio",
          body_text: "This is the transcription",
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "uses transcription as text" do
        expect(turn[:text]).to eq("This is the transcription")
      end
    end

    context "with audio message without transcription" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.audio456",
          type_name: "audio",
          body_text: nil,
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "uses placeholder text" do
        expect(turn[:text]).to eq("[Audio message]")
      end
    end

    context "with location message" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.location123",
          type_name: "location",
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "formats location text" do
        expect(turn[:text]).to eq("[Location shared]")
      end
    end

    context "with document message" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.doc123",
          type_name: "document",
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "formats document message appropriately" do
        expect(turn[:text]).to eq("[Document shared]")
      end
    end

    context "with document message without filename" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.doc456",
          type_name: "document",
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "uses generic document text" do
        expect(turn[:text]).to eq("[Document shared]")
      end
    end

    context "with contacts message" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.contact123",
          type_name: "contacts",
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "uses placeholder text for contacts" do
        expect(turn[:text]).to eq("[Contact card shared]")
      end
    end

    context "with image/video/sticker message" do
      %w[image video sticker].each do |media_type|
        context "with #{media_type} type" do
          let(:wa_message) do
            create(:wa_message,
              wa_contact: wa_contact,
              wa_business_number: wa_business_number,
              provider_message_id: "wamid.#{media_type}123",
              type_name: media_type,
              timestamp: Time.current
            )
          end

          let(:turn) { described_class.new(wa_message).build }

          it "formats media text" do
            expect(turn[:text]).to eq("[#{media_type.capitalize} shared]")
          end
        end
      end
    end

    context "with unknown message type" do
      let(:wa_message) do
        create(:wa_message,
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          provider_message_id: "wamid.unknown123",
          type_name: "unknown_type",
          body_text: nil,
          timestamp: Time.current
        )
      end

      let(:turn) { described_class.new(wa_message).build }

      it "uses generic placeholder with type" do
        expect(turn[:text]).to eq("[unknown_type message]")
      end
    end
  end
end
