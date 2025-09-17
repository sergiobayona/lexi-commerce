require "rails_helper"

RSpec.describe Whatsapp::Responders::WelcomeResponder do
  let(:business_number) { WaBusinessNumber.create!(phone_number_id: "111", display_phone_number: "15550000000") }
  let(:contact) { WaContact.create!(wa_id: "16505551234", profile_name: "Maria") }
  let(:now) { Time.zone.now.change(usec: 0) }

  def build_message!(provider_id:, body:, timestamp: now)
    WaMessage.create!(
      provider_message_id: provider_id,
      direction: "inbound",
      wa_contact: contact,
      wa_business_number: business_number,
      type_name: "text",
      body_text: body,
      timestamp: timestamp,
      status: "received",
      has_media: false,
      media_kind: nil,
      raw: {}
    )
  end

  describe "#call" do
    let(:value) { { "metadata" => {}, "contacts" => [{ "wa_id" => contact.wa_id }] } }
    let(:msg) { { "id" => "wamid.test", "timestamp" => now.to_i } }

    context "when message exists" do
      before do
        build_message!(provider_id: "wamid.test", body: greeting_text)
      end

      context "with Spanish greeting" do
        let(:greeting_text) { "hola" }

        it "returns Spanish welcome message" do
          responder = described_class.new(value, msg)
          result = responder.call

          expect(result).to include("¡Hola! 👋 ¡Bienvenido/a a Lexi!")
          expect(result).to include("Soy tu asistente de aprendizaje de inglés")
          expect(result).to include("¿En qué te gustaría practicar hoy?")
        end

        it "logs the welcome attempt with Spanish language detection" do
          allow(Rails.logger).to receive(:info)

          responder = described_class.new(value, msg)
          responder.call

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              "at" => "welcome_responder.sending",
              "welcome_language" => "spanish"
            )
          )
        end
      end

      context "with English greeting" do
        let(:greeting_text) { "hello" }

        it "returns English welcome message" do
          responder = described_class.new(value, msg)
          result = responder.call

          expect(result).to include("Hello! 👋 Welcome to Lexi!")
          expect(result).to include("I'm your English learning assistant")
          expect(result).to include("What would you like to practice today?")
        end

        it "logs the welcome attempt with English language detection" do
          allow(Rails.logger).to receive(:info)

          responder = described_class.new(value, msg)
          responder.call

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              "at" => "welcome_responder.sending",
              "welcome_language" => "english"
            )
          )
        end
      end

      context "with mixed language greeting" do
        let(:greeting_text) { "hola how are you" }

        it "returns bilingual welcome message" do
          responder = described_class.new(value, msg)
          result = responder.call

          expect(result).to include("¡Hola! Hi! 👋 Welcome to Lexi!")
          expect(result).to include("I'm your English learning assistant / Soy tu asistente")
          expect(result).to include("What would you like to practice today? / ¿En qué te gustaría practicar hoy?")
        end

        it "logs the welcome attempt with mixed language detection" do
          allow(Rails.logger).to receive(:info)

          responder = described_class.new(value, msg)
          responder.call

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              "at" => "welcome_responder.sending",
              "welcome_language" => "mixed"
            )
          )
        end
      end

      context "logs what message would be sent" do
        let(:greeting_text) { "hello" }

        it "logs the message details" do
          allow(Rails.logger).to receive(:info)

          responder = described_class.new(value, msg)
          responder.call

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              "at" => "welcome_responder.would_send",
              "to" => contact.wa_id,
              "from" => business_number.display_phone_number
            )
          )
        end
      end
    end

    context "when message does not exist" do
      it "returns nil without error" do
        responder = described_class.new(value, { "id" => "nonexistent" })
        result = responder.call

        expect(result).to be_nil
      end
    end

    context "when an error occurs" do
      before do
        build_message!(provider_id: "wamid.test", body: "hello")
        allow(WaMessage).to receive(:find_by).and_raise(StandardError.new("test error"))
      end

      it "logs the error and returns nil" do
        allow(Rails.logger).to receive(:error)

        responder = described_class.new(value, msg)
        result = responder.call

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error) do |payload|
          parsed = JSON.parse(payload)
          parsed["at"] == "welcome_responder.error" &&
            parsed["error"] == "StandardError" &&
            parsed["message"] == "test error"
        end
      end
    end
  end

  describe "language detection" do
    let(:responder) { described_class.new({}, {}) }

    it "detects Spanish greetings" do
      spanish_greetings = ["hola", "buenos días", "buenas tardes", "qué tal", "cómo estás"]

      spanish_greetings.each do |greeting|
        expect(responder.send(:detect_language, greeting)).to eq(:spanish),
          "Expected '#{greeting}' to be detected as Spanish"
      end
    end

    it "detects mixed language greetings" do
      mixed_greetings = ["hola how are you", "hi cómo estás", "hello qué tal"]

      mixed_greetings.each do |greeting|
        expect(responder.send(:detect_language, greeting)).to eq(:mixed),
          "Expected '#{greeting}' to be detected as mixed"
      end
    end

    it "defaults to English for other greetings" do
      english_greetings = ["hello", "hi", "hey", "good morning"]

      english_greetings.each do |greeting|
        expect(responder.send(:detect_language, greeting)).to eq(:english),
          "Expected '#{greeting}' to be detected as English"
      end
    end
  end
end