# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Validator do
  let(:validator) { described_class.new }

  describe "#call!" do
    context "with valid state" do
      let(:valid_state) do
        {
          "meta" => {
            "tenant_id" => "tenant_123",
            "wa_id" => "16505551234",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {
            "turns" => [],
            "last_user_msg_id" => nil
          },
          "slots" => {
            "location_id" => nil
          },
          "version" => 3
        }
      end

      it "returns true" do
        expect(validator.call!(valid_state)).to be true
      end

      it "does not raise an error" do
        expect { validator.call!(valid_state) }.not_to raise_error
      end
    end

    context "with valid commerce lane" do
      let(:commerce_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "en-US",
            "timezone" => "America/New_York",
            "current_lane" => "commerce"
          },
          "dialogue" => { "turns" => [] },
          "slots" => {},
          "version" => 3
        }
      end

      it "returns true" do
        expect(validator.call!(commerce_state)).to be true
      end
    end

    context "with valid support lane" do
      let(:support_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-MX",
            "timezone" => "America/Mexico_City",
            "current_lane" => "support"
          },
          "dialogue" => { "turns" => [] },
          "slots" => {},
          "version" => 3
        }
      end

      it "returns true" do
        expect(validator.call!(support_state)).to be true
      end
    end

    context "with invalid state type" do
      it "raises Invalid error for nil" do
        expect {
          validator.call!(nil)
        }.to raise_error(State::Validator::Invalid, "state must be a Hash")
      end

      it "raises Invalid error for string" do
        expect {
          validator.call!("state")
        }.to raise_error(State::Validator::Invalid, "state must be a Hash")
      end

      it "raises Invalid error for array" do
        expect {
          validator.call!([])
        }.to raise_error(State::Validator::Invalid, "state must be a Hash")
      end

      it "raises Invalid error for integer" do
        expect {
          validator.call!(123)
        }.to raise_error(State::Validator::Invalid, "state must be a Hash")
      end
    end

    context "with missing required keys" do
      it "raises Invalid error for missing meta" do
        state = {
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, /missing keys: meta/)
      end

      it "raises Invalid error for missing dialogue" do
        state = {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, /missing keys: dialogue/)
      end

      it "raises Invalid error for missing slots" do
        state = {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, /missing keys: slots/)
      end

      it "raises Invalid error for missing version" do
        state = {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {}
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, /missing keys: version/)
      end

      it "raises Invalid error for multiple missing keys" do
        state = {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          }
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, /missing keys:/)
      end
    end

    context "with invalid meta structure" do
      it "raises Invalid error when meta is not a Hash" do
        state = {
          "meta" => "not a hash",
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta must be a Hash")
      end

      it "raises Invalid error when meta is an array" do
        state = {
          "meta" => [],
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta must be a Hash")
      end

      it "raises Invalid error when meta is nil" do
        state = {
          "meta" => nil,
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta must be a Hash")
      end
    end

    context "with missing meta fields" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "raises Invalid error for missing tenant_id" do
        state = base_state.deep_dup
        state["meta"]["tenant_id"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta.tenant_id missing")
      end

      it "raises Invalid error for missing wa_id" do
        state = base_state.deep_dup
        state["meta"]["wa_id"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta.wa_id missing")
      end

      it "raises Invalid error for missing locale" do
        state = base_state.deep_dup
        state["meta"]["locale"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta.locale missing")
      end

      it "raises Invalid error for missing timezone" do
        state = base_state.deep_dup
        state["meta"]["timezone"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta.timezone missing")
      end

      it "raises Invalid error for missing current_lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta.current_lane missing")
      end

      it "allows sticky_until to be nil" do
        state = base_state.deep_dup
        state["meta"]["sticky_until"] = nil

        expect { validator.call!(state) }.not_to raise_error
      end
    end

    context "with invalid lane values" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "raises Invalid error for invalid lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "invalid_lane"

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "invalid lane invalid_lane")
      end

      it "raises Invalid error for empty string lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = ""

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "invalid lane ")
      end

      it "raises Invalid error for uppercase lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "INFO"

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "invalid lane INFO")
      end

      it "raises Invalid error for mixed case lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "Info"

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "invalid lane Info")
      end

      it "raises Invalid error for typo in lane name" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "infos"

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "invalid lane infos")
      end
    end

    context "with valid lanes" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "accepts 'info' lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "info"

        expect(validator.call!(state)).to be true
      end

      it "accepts 'commerce' lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "commerce"

        expect(validator.call!(state)).to be true
      end

      it "accepts 'support' lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "support"

        expect(validator.call!(state)).to be true
      end
    end

    context "with extra fields" do
      let(:state_with_extras) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info",
            "extra_field" => "extra_value",
            "flags" => { "vip" => true }
          },
          "dialogue" => {
            "turns" => [ { "role" => "user", "text" => "hi" } ],
            "extra_dialogue_field" => "value"
          },
          "slots" => {
            "location_id" => "loc123",
            "extra_slot" => "value"
          },
          "commerce" => {
            "cart" => { "items" => [] }
          },
          "support" => {
            "active_case_id" => nil
          },
          "version" => 3,
          "extra_top_level" => "value"
        }
      end

      it "accepts state with extra fields" do
        expect(validator.call!(state_with_extras)).to be true
      end

      it "does not validate extra fields" do
        # Extra fields are ignored, not validated
        expect { validator.call!(state_with_extras) }.not_to raise_error
      end
    end

    context "with minimal valid state" do
      let(:minimal_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "accepts minimal state" do
        expect(validator.call!(minimal_state)).to be true
      end
    end

    context "with empty hash values" do
      let(:state_with_empty_hashes) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "accepts empty dialogue hash" do
        expect(validator.call!(state_with_empty_hashes)).to be true
      end

      it "accepts empty slots hash" do
        expect(validator.call!(state_with_empty_hashes)).to be true
      end
    end

    context "edge cases" do
      it "validates state from Contract.blank" do
        state = State::Contract.blank
        state["meta"]["tenant_id"] = "t1"
        state["meta"]["wa_id"] = "wa1"

        expect(validator.call!(state)).to be true
      end

      it "validates state created by Builder" do
        state = State::Builder.new.new_session(
          tenant_id: "t1",
          wa_id: "wa1"
        )

        expect(validator.call!(state)).to be true
      end

      it "raises error for empty hash" do
        expect {
          validator.call!({})
        }.to raise_error(State::Validator::Invalid, /missing keys/)
      end
    end

    context "with different locale values" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "accepts en-US locale" do
        state = base_state.deep_dup
        state["meta"]["locale"] = "en-US"

        expect(validator.call!(state)).to be true
      end

      it "accepts es-MX locale" do
        state = base_state.deep_dup
        state["meta"]["locale"] = "es-MX"

        expect(validator.call!(state)).to be true
      end

      it "accepts custom locale format" do
        state = base_state.deep_dup
        state["meta"]["locale"] = "pt-BR"

        expect(validator.call!(state)).to be true
      end

      it "does not validate locale format" do
        # Validator only checks presence, not format
        state = base_state.deep_dup
        state["meta"]["locale"] = "invalid"

        expect(validator.call!(state)).to be true
      end
    end

    context "with different timezone values" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }
      end

      it "accepts America/New_York timezone" do
        state = base_state.deep_dup
        state["meta"]["timezone"] = "America/New_York"

        expect(validator.call!(state)).to be true
      end

      it "accepts Europe/London timezone" do
        state = base_state.deep_dup
        state["meta"]["timezone"] = "Europe/London"

        expect(validator.call!(state)).to be true
      end

      it "does not validate timezone format" do
        # Validator only checks presence, not format
        state = base_state.deep_dup
        state["meta"]["timezone"] = "InvalidTimeZone"

        expect(validator.call!(state)).to be true
      end
    end

    context "validation order" do
      it "checks state type before checking keys" do
        expect {
          validator.call!("not a hash")
        }.to raise_error(State::Validator::Invalid, "state must be a Hash")
      end

      it "checks required keys before meta structure" do
        state = {
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, /missing keys: meta/)
      end

      it "checks meta structure before meta fields" do
        state = {
          "meta" => "not a hash",
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta must be a Hash")
      end

      it "checks meta fields before lane validation" do
        state = {
          "meta" => {
            "tenant_id" => nil
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta.tenant_id missing")
      end
    end

    context "error messages" do
      it "provides specific error message for state type" do
        expect {
          validator.call!(nil)
        }.to raise_error(State::Validator::Invalid) do |error|
          expect(error.message).to eq("state must be a Hash")
        end
      end

      it "provides specific error message for missing keys" do
        expect {
          validator.call!({ "meta" => {} })
        }.to raise_error(State::Validator::Invalid) do |error|
          expect(error.message).to match(/missing keys:/)
          expect(error.message).to match(/dialogue/)
          expect(error.message).to match(/slots/)
          expect(error.message).to match(/version/)
        end
      end

      it "provides specific error message for meta type" do
        state = {
          "meta" => [],
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid) do |error|
          expect(error.message).to eq("meta must be a Hash")
        end
      end

      it "provides specific error message for missing meta field" do
        state = {
          "meta" => {
            "tenant_id" => nil,
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid) do |error|
          expect(error.message).to eq("meta.tenant_id missing")
        end
      end

      it "provides specific error message for invalid lane" do
        state = {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "locale" => "es-CO",
            "timezone" => "America/Bogota",
            "current_lane" => "checkout"
          },
          "dialogue" => {},
          "slots" => {},
          "version" => 3
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid) do |error|
          expect(error.message).to eq("invalid lane checkout")
        end
      end
    end

    describe State::Validator::Invalid do
      it "is a StandardError subclass" do
        expect(State::Validator::Invalid.new).to be_a(StandardError)
      end

      it "can be rescued as StandardError" do
        expect {
          begin
            raise State::Validator::Invalid, "test error"
          rescue StandardError
            # Successfully rescued
          end
        }.not_to raise_error
      end
    end
  end
end
