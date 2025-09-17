require "rails_helper"

RSpec.describe Whatsapp::Intent::Evaluator do
  let(:business_number) { WaBusinessNumber.create!(phone_number_id: "111", display_phone_number: "15550000000") }
  let(:contact) { WaContact.create!(wa_id: "16505551234", profile_name: "Alice") }

  def build_message!(provider_id:, body:, timestamp:, contact: self.contact)
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
    let(:now) { Time.zone.now.change(usec: 0) }

    it "returns nil when message is not found" do
      evaluator = described_class.new(value: {}, msg: { "id" => "missing-id" })
      expect(evaluator.call).to be_nil
    end

    it "logs evaluated intent details" do
      build_message!(provider_id: "wamid.1", body: "hi there", timestamp: now)

      logged = nil
      allow(Rails.logger).to receive(:info) do |payload|
        begin
          parsed = JSON.parse(payload)
          logged = parsed if parsed["at"] == "intent.evaluated"
        rescue JSON::ParserError
          # ignore non-JSON logs
        end
      end

      result = described_class.new(value: {}, msg: { "id" => "wamid.1" }).call

      expect(result[:label]).to eq(:onboard_greeting)
      expect(logged).to be_present
      expect(logged["provider_message_id"]).to eq("wamid.1")
      expect(logged["contact_id"]).to eq(contact.id)
      expect(logged["first_interaction"]).to be true
      expect(logged["intent_label"]).to eq("onboard_greeting")
      expect(logged["confidence"]).to be_a(Float)
      expect(logged["rationale"]).to be_a(String)
    end

    it "rescues and logs errors, returning nil" do
      allow(WaMessage).to receive(:find_by).and_raise(StandardError.new("boom"))

      error_log = nil
      allow(Rails.logger).to receive(:error) do |payload|
        begin
          parsed = JSON.parse(payload)
          error_log = parsed if parsed["at"] == "intent.error"
        rescue JSON::ParserError
        end
      end

      evaluator = described_class.new(value: {}, msg: { "id" => "any" })
      expect(evaluator.call).to be_nil

      expect(error_log).to be_present
      expect(error_log["error"]).to eq("StandardError")
      expect(error_log["message"]).to eq("boom")
    end

    context "first interaction" do
      it "returns onboard_greeting for greeting text with high confidence" do
        build_message!(provider_id: "wamid.2", body: "Hello!", timestamp: now)

        result = described_class.new(value: {}, msg: { "id" => "wamid.2" }).call
        expect(result).to include(label: :onboard_greeting, confidence: 0.8)
        expect(result[:rationale]).to include("Greeting on first interaction")
      end

      it "recognizes Spanish basic greetings" do
        [
          "hola",
          "buenos días",
          "buenas tardes",
          "buenas noches",
          "buenas"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.spanish.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
          expect(result[:rationale]).to include("Greeting on first interaction")
        end
      end

      it "recognizes Spanish greetings without accents" do
        [
          "buenos dias",
          "como estas",
          "que tal"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.no_accents.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "recognizes Spanish 'how are you' variations" do
        [
          "¿cómo estás?",
          "como estas",
          "¿qué tal?",
          "que pasa",
          "¿qué onda?",
          "¿cómo andas?"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.how_are_you.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "recognizes casual Spanish greetings" do
        [
          "holi",
          "holita",
          "saludos",
          "ey",
          "oye"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.casual.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "recognizes regional Spanish variations" do
        [
          "quihubo",
          "qué más",
          "epale",
          "wey",
          "güey",
          "hermano",
          "bro"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.regional.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "recognizes internet slang and abbreviations" do
        [
          "q tal",
          "k pasa",
          "q onda"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.slang.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "recognizes mixed English-Spanish greetings" do
        [
          "hola how are you",
          "hi cómo estás",
          "hello qué tal",
          "hey hola"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.mixed.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "recognizes formal Spanish greetings" do
        [
          "muy buenos días",
          "tengan buen día",
          "que tengas buen día",
          "cordial saludo"
        ].each_with_index do |greeting, index|
          provider_id = "wamid.formal.#{index}"
          build_message!(provider_id: provider_id, body: greeting, timestamp: now)

          result = described_class.new(value: {}, msg: { "id" => provider_id }).call
          expect(result).to include(label: :onboard_greeting, confidence: 0.8),
            "Expected '#{greeting}' to be recognized as onboard_greeting"
        end
      end

      it "matches :help rule when keywords present" do
        build_message!(provider_id: "wamid.3", body: "I need help with setup", timestamp: now)

        result = described_class.new(value: {}, msg: { "id" => "wamid.3" }).call
        expect(result).to include(label: :help, confidence: 0.7)
        expect(result[:rationale]).to include("Matched pattern help")
      end

      it "falls back to onboard_greeting with lower confidence when no rule matched" do
        build_message!(provider_id: "wamid.4", body: "Just some random text", timestamp: now)

        result = described_class.new(value: {}, msg: { "id" => "wamid.4" }).call
        expect(result).to include(label: :onboard_greeting, confidence: 0.6)
        expect(result[:rationale]).to include("First interaction without clear keywords")
      end
    end

    context "subsequent interaction" do
      let(:earlier) { now - 5.minutes }

      before do
        # Prior inbound message from same contact ensures not first interaction
        build_message!(provider_id: "wamid.prev", body: "earlier message", timestamp: earlier)
      end

      it "still matches rules (e.g., :help) regardless of first interaction" do
        build_message!(provider_id: "wamid.5", body: "help please", timestamp: now)

        result = described_class.new(value: {}, msg: { "id" => "wamid.5" }).call
        expect(result).to include(label: :help, confidence: 0.7)
      end

      it "does not treat greetings specially and returns :unknown when no rule matches" do
        build_message!(provider_id: "wamid.6", body: "hey there", timestamp: now)

        result = described_class.new(value: {}, msg: { "id" => "wamid.6" }).call
        expect(result).to include(label: :unknown, confidence: 0.3)
        expect(result[:rationale]).to include("No rule matched")
      end
    end

    context "rule coverage" do
      it "matches :summarize keywords" do
        build_message!(provider_id: "wamid.7", body: "TL;DR please summarize this", timestamp: now)
        result = described_class.new(value: {}, msg: { "id" => "wamid.7" }).call
        expect(result[:label]).to eq(:summarize)
      end

      it "matches :extract keywords" do
        build_message!(provider_id: "wamid.8", body: "can you extract key points?", timestamp: now)
        result = described_class.new(value: {}, msg: { "id" => "wamid.8" }).call
        expect(result[:label]).to eq(:extract)
      end

      it "matches :translate keywords" do
        build_message!(provider_id: "wamid.9", body: "translation to Spanish", timestamp: now)
        result = described_class.new(value: {}, msg: { "id" => "wamid.9" }).call
        expect(result[:label]).to eq(:translate)
      end

      it "matches :upload_doc keywords" do
        build_message!(provider_id: "wamid.10", body: "upload the pdf document", timestamp: now)
        result = described_class.new(value: {}, msg: { "id" => "wamid.10" }).call
        expect(result[:label]).to eq(:upload_doc)
      end

      it "matches :voice_note keywords" do
        build_message!(provider_id: "wamid.11", body: "this is a voice note", timestamp: now)
        result = described_class.new(value: {}, msg: { "id" => "wamid.11" }).call
        expect(result[:label]).to eq(:voice_note)
      end
    end
  end
end
