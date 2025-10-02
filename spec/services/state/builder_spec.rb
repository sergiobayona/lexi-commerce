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
        expect(session["meta"]["tenant_id"]).to eq("tenant_123")
        expect(session["meta"]["wa_id"]).to eq("16505551234")
      end

      it "applies default locale" do
        expect(session["meta"]["locale"]).to eq("es-CO")
      end

      it "applies default timezone" do
        expect(session["meta"]["timezone"]).to eq("America/Bogota")
      end

      it "includes all required sections from Contract" do
        expect(session).to have_key("meta")
        expect(session).to have_key("dialogue")
        expect(session).to have_key("slots")
        expect(session).to have_key("commerce")
        expect(session).to have_key("support")
        expect(session).to have_key("version")
      end

      it "sets current version" do
        expect(session["version"]).to eq(State::Contract::CURRENT_VERSION)
      end

      it "includes default meta fields" do
        expect(session["meta"]["current_lane"]).to eq("info")
        expect(session["meta"]["flags"]).to eq({ "human_handoff" => false, "vip" => false })
      end

      it "includes empty dialogue structure" do
        expect(session["dialogue"]["turns"]).to eq([])
        expect(session["dialogue"]["last_user_msg_id"]).to be_nil
        expect(session["dialogue"]["last_assistant_msg_id"]).to be_nil
      end

      it "includes default slots" do
        expect(session["slots"]["phone_verified"]).to be false
        expect(session["slots"]["language_locked"]).to be false
      end

      it "includes default commerce state" do
        expect(session["commerce"]["state"]).to eq("browsing")
        expect(session["commerce"]["cart"]["items"]).to eq([])
        expect(session["commerce"]["cart"]["currency"]).to eq("COP")
      end

      it "includes default support state" do
        expect(session["support"]["active_case_id"]).to be_nil
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
        expect(session["meta"]["locale"]).to eq("en-US")
      end

      it "applies custom timezone" do
        expect(session["meta"]["timezone"]).to eq("America/New_York")
      end

      it "still sets tenant_id and wa_id correctly" do
        expect(session["meta"]["tenant_id"]).to eq("tenant_456")
        expect(session["meta"]["wa_id"]).to eq("16505559999")
      end
    end

    context "independence of sessions" do
      it "creates independent copies" do
        session1 = builder.new_session(tenant_id: "t1", wa_id: "wa1")
        session2 = builder.new_session(tenant_id: "t2", wa_id: "wa2")

        session1["meta"]["current_lane"] = "commerce"
        session1["commerce"]["cart"]["items"] << { "id" => "item1" }

        expect(session2["meta"]["current_lane"]).to eq("info")
        expect(session2["commerce"]["cart"]["items"]).to eq([])
      end

      it "does not mutate Contract defaults" do
        original_defaults = State::Contract::DEFAULTS.deep_dup

        session = builder.new_session(tenant_id: "t1", wa_id: "wa1")
        session["meta"]["flags"]["vip"] = true
        session["dialogue"]["turns"] << { "role" => "user", "text" => "hi" }

        expect(State::Contract::DEFAULTS).to eq(original_defaults)
      end
    end
  end

  describe "#from_json" do
    context "with valid JSON string" do
      let(:json_state) do
        {
          "meta" => {
            "tenant_id" => "tenant_789",
            "wa_id" => "16505554321",
            "locale" => "es-MX",
            "timezone" => "America/Mexico_City",
            "current_lane" => "commerce"
          },
          "dialogue" => {
            "turns" => [ { "role" => "user", "text" => "hola" } ],
            "last_user_msg_id" => "msg_123"
          },
          "version" => State::Contract::CURRENT_VERSION
        }.to_json
      end

      it "parses JSON and hydrates state" do
        state = builder.from_json(json_state)

        expect(state["meta"]["tenant_id"]).to eq("tenant_789")
        expect(state["meta"]["wa_id"]).to eq("16505554321")
        expect(state["meta"]["locale"]).to eq("es-MX")
        expect(state["meta"]["current_lane"]).to eq("commerce")
      end

      it "preserves existing values" do
        state = builder.from_json(json_state)

        expect(state["dialogue"]["turns"].size).to eq(1)
        expect(state["dialogue"]["turns"].first["role"]).to eq("user")
        expect(state["dialogue"]["last_user_msg_id"]).to eq("msg_123")
      end

      it "fills missing defaults from Contract" do
        state = builder.from_json(json_state)

        # slots section not in JSON, should be filled with defaults
        expect(state["slots"]).to be_present
        expect(state["slots"]["phone_verified"]).to be false
        expect(state["slots"]["language_locked"]).to be false

        # commerce section not in JSON
        expect(state["commerce"]).to be_present
        expect(state["commerce"]["state"]).to eq("browsing")

        # support section not in JSON
        expect(state["support"]).to be_present
        expect(state["support"]["active_case_id"]).to be_nil
      end

      it "fills missing nested defaults" do
        partial_json = {
          "meta" => { "tenant_id" => "t1", "wa_id" => "wa1" },
          "version" => State::Contract::CURRENT_VERSION
        }.to_json

        state = builder.from_json(partial_json)

        # meta fields should be filled
        expect(state["meta"]["locale"]).to eq("es-CO")
        expect(state["meta"]["timezone"]).to eq("America/Bogota")
        expect(state["meta"]["current_lane"]).to eq("info")
        expect(state["meta"]["flags"]).to eq({ "human_handoff" => false, "vip" => false })
      end
    end

    context "with nil input" do
      it "creates blank state with all defaults" do
        state = builder.from_json(nil)

        expect(state["meta"]).to be_present
        expect(state["dialogue"]).to be_present
        expect(state["slots"]).to be_present
        expect(state["version"]).to eq(State::Contract::CURRENT_VERSION)
      end
    end

    context "with empty string" do
      it "creates blank state with all defaults" do
        state = builder.from_json("")

        expect(state["meta"]).to be_present
        expect(state["dialogue"]).to be_present
        expect(state["slots"]).to be_present
        expect(state["version"]).to eq(State::Contract::CURRENT_VERSION)
      end
    end

    context "with single character string" do
      it "creates blank state with all defaults" do
        state = builder.from_json("{")

        expect(state["meta"]).to be_present
        expect(state["dialogue"]).to be_present
        expect(state["slots"]).to be_present
        expect(state["version"]).to eq(State::Contract::CURRENT_VERSION)
      end
    end

    context "with old version requiring upcast" do
      let(:old_version_json) do
        {
          "meta" => { "tenant_id" => "t1", "wa_id" => "wa1" },
          "version" => 1
        }.to_json
      end

      it "triggers upcaster for old version" do
        upcaster = instance_double(State::Upcaster)
        allow(State::Upcaster).to receive(:new).and_return(upcaster)
        allow(upcaster).to receive(:call) do |state|
          state["version"] = State::Contract::CURRENT_VERSION
          state
        end

        state = builder.from_json(old_version_json)

        expect(State::Upcaster).to have_received(:new)
        expect(upcaster).to have_received(:call)
      end

      it "returns upcasted state" do
        upcaster = instance_double(State::Upcaster)
        allow(State::Upcaster).to receive(:new).and_return(upcaster)
        allow(upcaster).to receive(:call) do |state|
          state["version"] = State::Contract::CURRENT_VERSION
          state["upcasted"] = true
          state
        end

        state = builder.from_json(old_version_json)

        expect(state["upcasted"]).to be true
        expect(state["version"]).to eq(State::Contract::CURRENT_VERSION)
      end
    end

    context "with current version" do
      let(:current_version_json) do
        {
          "meta" => { "tenant_id" => "t1", "wa_id" => "wa1" },
          "version" => State::Contract::CURRENT_VERSION
        }.to_json
      end

      it "skips upcasting for current version" do
        upcaster = instance_double(State::Upcaster)
        allow(State::Upcaster).to receive(:new).and_return(upcaster)

        builder.from_json(current_version_json)

        expect(State::Upcaster).not_to have_received(:new)
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
      it "merges nested hashes recursively" do
        json_state = {
          "meta" => {
            "tenant_id" => "new_tenant",
            "custom_field" => "custom_value"
          },
          "commerce" => {
            "cart" => {
              "items" => [ { "id" => 1 } ],
              "subtotal_cents" => 500
            }
          },
          "version" => State::Contract::CURRENT_VERSION
        }.to_json

        state = builder.from_json(json_state)

        # Preserves new values
        expect(state["meta"]["tenant_id"]).to eq("new_tenant")
        expect(state["meta"]["custom_field"]).to eq("custom_value")

        # Fills missing meta defaults
        expect(state["meta"]["locale"]).to eq("es-CO")
        expect(state["meta"]["timezone"]).to eq("America/Bogota")

        # Preserves nested commerce values
        expect(state["commerce"]["cart"]["items"].size).to eq(1)
        expect(state["commerce"]["cart"]["subtotal_cents"]).to eq(500)

        # Fills missing nested defaults
        expect(state["commerce"]["cart"]["currency"]).to eq("COP")
        expect(state["commerce"]["state"]).to eq("browsing")
      end

      it "replaces arrays rather than merging" do
        json_state = {
          "dialogue" => {
            "turns" => [ { "role" => "user", "text" => "hi" } ]
          },
          "version" => State::Contract::CURRENT_VERSION
        }.to_json

        state = builder.from_json(json_state)

        # Array should be replaced, not merged with default empty array
        expect(state["dialogue"]["turns"]).to eq([ { "role" => "user", "text" => "hi" } ])
      end

      it "replaces scalar values rather than merging" do
        json_state = {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "current_lane" => "support"
          },
          "version" => State::Contract::CURRENT_VERSION
        }.to_json

        state = builder.from_json(json_state)

        # Scalar should be replaced, not use default
        expect(state["meta"]["current_lane"]).to eq("support")
      end
    end
  end

  describe "integration with Contract" do
    it "uses Contract.blank for defaults" do
      allow(State::Contract).to receive(:blank).and_call_original

      builder.new_session(tenant_id: "t1", wa_id: "wa1")

      expect(State::Contract).to have_received(:blank)
    end

    it "uses Contract.current_version? for version checking" do
      allow(State::Contract).to receive(:current_version?).and_call_original

      json = { "version" => State::Contract::CURRENT_VERSION }.to_json
      builder.from_json(json)

      expect(State::Contract).to have_received(:current_version?)
    end
  end

  describe "thread safety" do
    it "creates independent state objects across threads" do
      results = []
      threads = []

      5.times do |i|
        threads << Thread.new do
          state = builder.new_session(tenant_id: "tenant_#{i}", wa_id: "wa_#{i}")
          state["meta"]["current_lane"] = "lane_#{i}"
          results << state["meta"]["current_lane"]
        end
      end

      threads.each(&:join)

      expect(results).to contain_exactly("lane_0", "lane_1", "lane_2", "lane_3", "lane_4")
    end
  end

  describe "edge cases" do
    it "handles state with missing version field" do
      json_state = {
        "meta" => { "tenant_id" => "t1", "wa_id" => "wa1" }
      }.to_json

      upcaster = instance_double(State::Upcaster)
      allow(State::Upcaster).to receive(:new).and_return(upcaster)
      allow(upcaster).to receive(:call) do |state|
        state["version"] = State::Contract::CURRENT_VERSION
        state
      end

      state = builder.from_json(json_state)

      expect(state["version"]).to eq(State::Contract::CURRENT_VERSION)
    end

    it "handles empty JSON object" do
      state = builder.from_json("{}")

      expect(state["meta"]).to be_present
      expect(state["dialogue"]).to be_present
      expect(state["slots"]).to be_present
      expect(state["version"]).to eq(State::Contract::CURRENT_VERSION)
    end

    it "handles deeply nested custom fields" do
      json_state = {
        "meta" => {
          "tenant_id" => "t1",
          "wa_id" => "wa1",
          "custom" => {
            "level1" => {
              "level2" => {
                "value" => "deep"
              }
            }
          }
        },
        "version" => State::Contract::CURRENT_VERSION
      }.to_json

      state = builder.from_json(json_state)

      expect(state["meta"]["custom"]["level1"]["level2"]["value"]).to eq("deep")
      expect(state["meta"]["locale"]).to eq("es-CO") # Still has defaults
    end
  end
end
