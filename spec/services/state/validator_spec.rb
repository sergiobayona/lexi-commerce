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
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {}
        }
      end

      it "returns true" do
        expect(validator.call!(valid_state)).to be true
      end

      it "does not raise an error" do
        expect { validator.call!(valid_state) }.not_to raise_error
      end
    end

    context "with invalid state type" do
      it "raises Invalid error for nil" do
        expect {
          validator.call!(nil)
        }.to raise_error(State::Validator::Invalid, "state must be Hash")
      end

      it "raises Invalid error for string" do
        expect {
          validator.call!("state")
        }.to raise_error(State::Validator::Invalid, "state must be Hash")
      end

      it "raises Invalid error for array" do
        expect {
          validator.call!([])
        }.to raise_error(State::Validator::Invalid, "state must be Hash")
      end
    end

    context "with invalid meta structure" do
      it "raises Invalid error when meta is not a Hash" do
        state = {
          "meta" => "not a hash",
          "dialogue" => {},
          "slots" => {}
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta missing")
      end

      it "raises Invalid error when meta is nil" do
        state = {
          "meta" => nil,
          "dialogue" => {},
          "slots" => {}
        }

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "meta missing")
      end
    end

    context "with missing meta fields" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {}
        }
      end

      it "raises Invalid error for missing tenant_id" do
        state = base_state.deep_dup
        state["meta"]["tenant_id"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "tenant_id missing")
      end

      it "raises Invalid error for missing wa_id" do
        state = base_state.deep_dup
        state["meta"]["wa_id"] = nil

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "wa_id missing")
      end
    end

    context "with invalid lane values" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {}
        }
      end

      it "raises Invalid error for invalid lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "invalid_lane"

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "current_lane invalid")
      end

      it "raises Invalid error for empty string lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = ""

        expect {
          validator.call!(state)
        }.to raise_error(State::Validator::Invalid, "current_lane invalid")
      end
    end

    context "with valid lanes" do
      let(:base_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
            "current_lane" => "info"
          },
          "dialogue" => {},
          "slots" => {}
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

      it "accepts 'product' lane" do
        state = base_state.deep_dup
        state["meta"]["current_lane"] = "product"

        expect(validator.call!(state)).to be true
      end
    end

    context "with extra fields" do
      let(:state_with_extras) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "wa_id" => "wa1",
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
          "extra_top_level" => "value"
        }
      end

      it "accepts state with extra fields" do
        expect(validator.call!(state_with_extras)).to be true
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
