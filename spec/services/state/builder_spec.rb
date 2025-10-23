# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Builder do
  let(:builder) { described_class.new }

  describe "#new_session" do
    context "with required parameters" do
      let(:session) do
        builder.new_session(
          tenant_id: "tenant_123",
          wa_id: "16505551234"
        )
      end

      it "creates a new session with provided tenant_id and wa_id" do
        expect(session["tenant_id"]).to eq("tenant_123")
        expect(session["wa_id"]).to eq("16505551234")
      end

      it "applies default locale" do
        expect(session["locale"]).to eq("es-CO")
      end

      it "applies default timezone" do
        expect(session["timezone"]).to eq("America/Bogota")
      end

      it "includes default routing fields" do
        expect(session["current_lane"]).to eq("info")
        expect(session["sticky_until"]).to be_nil
      end

      it "includes default customer flags" do
        expect(session["human_handoff"]).to be false
        expect(session["vip"]).to be false
      end

      it "includes empty dialogue structure" do
        expect(session["turns"]).to eq([])
        expect(session["last_user_msg_id"]).to be_nil
        expect(session["last_assistant_msg_id"]).to be_nil
      end

      it "includes default slots" do
        expect(session["phone_verified"]).to be false
        expect(session["language_locked"]).to be false
      end

      it "includes default commerce state" do
        expect(session["commerce_state"]).to eq("browsing")
        expect(session["cart_items"]).to eq([])
        expect(session["cart_currency"]).to eq("COP")
      end

      it "includes default support state" do
        expect(session["active_case_id"]).to be_nil
      end
    end

    context "with custom locale and timezone" do
      let(:session) do
        builder.new_session(
          tenant_id: "tenant_456",
          wa_id: "16505559999",
          locale: "en-US",
          timezone: "America/New_York"
        )
      end

      it "applies custom locale" do
        expect(session["locale"]).to eq("en-US")
      end

      it "applies custom timezone" do
        expect(session["timezone"]).to eq("America/New_York")
      end

      it "still sets tenant_id and wa_id correctly" do
        expect(session["tenant_id"]).to eq("tenant_456")
        expect(session["wa_id"]).to eq("16505559999")
      end
    end

    context "independence of sessions" do
      it "creates independent copies" do
        session1 = builder.new_session(tenant_id: "t1", wa_id: "wa1")
        session2 = builder.new_session(tenant_id: "t2", wa_id: "wa2")

        session1["current_lane"] = "commerce"
        session1["cart_items"] << { "id" => "item1" }

        expect(session2["current_lane"]).to eq("info")
        expect(session2["cart_items"]).to eq([])
      end

      it "does not mutate Contract defaults" do
        original_defaults = State::Contract::DEFAULTS.deep_dup

        session = builder.new_session(tenant_id: "t1", wa_id: "wa1")
        session["vip"] = true
        session["turns"] << { "role" => "user", "text" => "hi" }

        expect(State::Contract::DEFAULTS).to eq(original_defaults)
      end
    end
  end

  describe "#from_json" do
    context "with valid JSON string" do
      let(:json_state) do
        {
          "tenant_id" => "tenant_789",
          "wa_id" => "16505554321",
          "locale" => "es-MX",
          "timezone" => "America/Mexico_City",
          "current_lane" => "commerce",
          "turns" => [ { "role" => "user", "text" => "hola" } ],
          "last_user_msg_id" => "msg_123"
        }.to_json
      end

      it "parses JSON and hydrates state" do
        state = builder.from_json(json_state)

        expect(state["tenant_id"]).to eq("tenant_789")
        expect(state["wa_id"]).to eq("16505554321")
        expect(state["locale"]).to eq("es-MX")
        expect(state["current_lane"]).to eq("commerce")
      end

      it "preserves existing values" do
        state = builder.from_json(json_state)

        expect(state["turns"].size).to eq(1)
        expect(state["turns"].first["role"]).to eq("user")
        expect(state["last_user_msg_id"]).to eq("msg_123")
      end

      it "fills missing defaults from Contract" do
        state = builder.from_json(json_state)

        # Fields not in JSON should be filled with defaults
        expect(state["phone_verified"]).to be false
        expect(state["language_locked"]).to be false
        expect(state["commerce_state"]).to eq("browsing")
        expect(state["active_case_id"]).to be_nil
      end

      it "fills missing fields" do
        partial_json = {
          "tenant_id" => "t1",
          "wa_id" => "wa1"
        }.to_json

        state = builder.from_json(partial_json)

        # Missing fields should be filled
        expect(state["locale"]).to eq("es-CO")
        expect(state["timezone"]).to eq("America/Bogota")
        expect(state["current_lane"]).to eq("info")
        expect(state["human_handoff"]).to be false
        expect(state["vip"]).to be false
      end
    end

    context "with nil input" do
      it "creates blank state with all defaults" do
        state = builder.from_json(nil)

        expect(state["tenant_id"]).to be_nil
        expect(state["wa_id"]).to be_nil
        expect(state["locale"]).to eq("es-CO")
        expect(state["turns"]).to eq([])
      end
    end

    context "with empty string" do
      it "creates blank state with all defaults" do
        state = builder.from_json("")

        expect(state["tenant_id"]).to be_nil
        expect(state["wa_id"]).to be_nil
        expect(state["locale"]).to eq("es-CO")
        expect(state["turns"]).to eq([])
      end
    end

    context "with single character string" do
      it "creates blank state with all defaults" do
        state = builder.from_json("{")

        expect(state["tenant_id"]).to be_nil
        expect(state["wa_id"]).to be_nil
        expect(state["locale"]).to eq("es-CO")
        expect(state["turns"]).to eq([])
      end
    end

    context "with invalid JSON" do
      it "raises JSON parse error" do
        expect {
          builder.from_json("invalid json{")
        }.to raise_error(JSON::ParserError)
      end
    end

    context "deep merge behavior" do
      it "merges flat hashes" do
        json_state = {
          "tenant_id" => "new_tenant",
          "custom_field" => "custom_value",
          "cart_items" => [ { "id" => 1 } ],
          "cart_subtotal_cents" => 500
        }.to_json

        state = builder.from_json(json_state)

        # Preserves new values
        expect(state["tenant_id"]).to eq("new_tenant")
        expect(state["custom_field"]).to eq("custom_value")

        # Fills missing defaults
        expect(state["locale"]).to eq("es-CO")
        expect(state["timezone"]).to eq("America/Bogota")

        # Preserves values from JSON
        expect(state["cart_items"].size).to eq(1)
        expect(state["cart_subtotal_cents"]).to eq(500)

        # Fills missing defaults
        expect(state["cart_currency"]).to eq("COP")
        expect(state["commerce_state"]).to eq("browsing")
      end

      it "replaces arrays rather than merging" do
        json_state = {
          "turns" => [ { "role" => "user", "text" => "hi" } ]
        }.to_json

        state = builder.from_json(json_state)

        # Array should be replaced, not merged with default empty array
        expect(state["turns"]).to eq([ { "role" => "user", "text" => "hi" } ])
      end

      it "replaces scalar values rather than merging" do
        json_state = {
          "tenant_id" => "t1",
          "wa_id" => "wa1",
          "current_lane" => "support"
        }.to_json

        state = builder.from_json(json_state)

        # Scalar should be replaced, not use default
        expect(state["current_lane"]).to eq("support")
      end
    end
  end

  describe "integration with Contract" do
    it "uses Contract.blank for defaults" do
      allow(State::Contract).to receive(:blank).and_call_original

      builder.new_session(tenant_id: "t1", wa_id: "wa1")

      expect(State::Contract).to have_received(:blank)
    end
  end

  describe "thread safety" do
    it "creates independent state objects across threads" do
      results = []
      threads = []

      5.times do |i|
        threads << Thread.new do
          state = builder.new_session(tenant_id: "tenant_#{i}", wa_id: "wa_#{i}")
          state["current_lane"] = "lane_#{i}"
          results << state["current_lane"]
        end
      end

      threads.each(&:join)

      expect(results).to contain_exactly("lane_0", "lane_1", "lane_2", "lane_3", "lane_4")
    end
  end

  describe "edge cases" do
    it "handles state with missing fields" do
      json_state = {
        "tenant_id" => "t1",
        "wa_id" => "wa1"
      }.to_json

      state = builder.from_json(json_state)

      expect(state).to be_a(Hash)
      expect(state["tenant_id"]).to eq("t1")
    end

    it "handles empty JSON object" do
      state = builder.from_json("{}")

      expect(state["tenant_id"]).to be_nil
      expect(state["locale"]).to eq("es-CO")
      expect(state["turns"]).to eq([])
    end

    it "handles custom fields" do
      json_state = {
        "tenant_id" => "t1",
        "wa_id" => "wa1",
        "custom" => {
          "level1" => {
            "level2" => {
              "value" => "deep"
            }
          }
        }
      }.to_json

      state = builder.from_json(json_state)

      expect(state["custom"]["level1"]["level2"]["value"]).to eq("deep")
      expect(state["locale"]).to eq("es-CO") # Still has defaults
    end
  end
end
