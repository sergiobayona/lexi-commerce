# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Contract do
  describe "constants" do
    describe "REQUIRED_KEYS" do
      it "is frozen" do
        expect(described_class::REQUIRED_KEYS).to be_frozen
      end

      it "contains essential structural keys" do
        expect(described_class::REQUIRED_KEYS).to eq(%w[tenant_id wa_id current_lane])
      end

      it "is an array of strings" do
        expect(described_class::REQUIRED_KEYS).to all(be_a(String))
      end
    end

    describe "DEFAULTS" do
      it "is frozen" do
        expect(described_class::DEFAULTS).to be_frozen
      end

      it "is a hash" do
        expect(described_class::DEFAULTS).to be_a(Hash)
      end

      it "contains all required keys" do
        described_class::REQUIRED_KEYS.each do |key|
          expect(described_class::DEFAULTS).to have_key(key)
        end
      end
    end
  end

  describe "DEFAULTS structure" do
    let(:defaults) { described_class::DEFAULTS }

    describe "session identity fields" do
      it "has tenant_id field" do
        expect(defaults["tenant_id"]).to be_nil
      end

      it "has wa_id field" do
        expect(defaults["wa_id"]).to be_nil
      end

      it "has locale field with default" do
        expect(defaults["locale"]).to eq("es-CO")
      end

      it "has timezone field with default" do
        expect(defaults["timezone"]).to eq("America/Bogota")
      end
    end

    describe "routing fields" do
      it "has current_lane field with default" do
        expect(defaults["current_lane"]).to eq("info")
      end

      it "has sticky_until field" do
        expect(defaults["sticky_until"]).to be_nil
      end
    end

    describe "customer fields" do
      it "has customer_id field" do
        expect(defaults["customer_id"]).to be_nil
      end

      it "has human_handoff flag" do
        expect(defaults["human_handoff"]).to be false
      end

      it "has vip flag" do
        expect(defaults["vip"]).to be false
      end
    end

    describe "dialogue fields" do
      it "has turns field" do
        expect(defaults["turns"]).to eq([])
      end

      it "has last_user_msg_id field" do
        expect(defaults["last_user_msg_id"]).to be_nil
      end

      it "has last_assistant_msg_id field" do
        expect(defaults["last_assistant_msg_id"]).to be_nil
      end
    end

    describe "slots fields" do
      it "has location_id field" do
        expect(defaults["location_id"]).to be_nil
      end

      it "has fulfillment field" do
        expect(defaults["fulfillment"]).to be_nil
      end

      it "has address field" do
        expect(defaults["address"]).to be_nil
      end

      it "has phone_verified field" do
        expect(defaults["phone_verified"]).to be false
      end

      it "has language_locked field" do
        expect(defaults["language_locked"]).to be false
      end
    end

    describe "commerce fields" do
      it "has commerce_state field" do
        expect(defaults["commerce_state"]).to eq("browsing")
      end

      it "has cart_items field" do
        expect(defaults["cart_items"]).to eq([])
      end

      it "has cart_subtotal_cents field" do
        expect(defaults["cart_subtotal_cents"]).to eq(0)
      end

      it "has cart_currency field" do
        expect(defaults["cart_currency"]).to eq("COP")
      end

      it "has last_quote field" do
        expect(defaults["last_quote"]).to be_nil
      end
    end

    describe "support fields" do
      it "has active_case_id field" do
        expect(defaults["active_case_id"]).to be_nil
      end

      it "has last_order_id field" do
        expect(defaults["last_order_id"]).to be_nil
      end

      it "has return_window_open field" do
        expect(defaults["return_window_open"]).to be_nil
      end
    end

    describe "misc fields" do
      it "has last_tool field" do
        expect(defaults["last_tool"]).to be_nil
      end

      it "has locked_agent field" do
        expect(defaults["locked_agent"]).to be_nil
      end

      it "has locked_until field" do
        expect(defaults["locked_until"]).to be_nil
      end
    end

    describe "metadata fields" do
      it "has updated_at field" do
        expect(defaults["updated_at"]).to be_nil
      end
    end

    describe "complete structure validation" do
      it "has all expected top-level keys" do
        expected_keys = %w[
          tenant_id wa_id locale timezone
          current_lane sticky_until
          customer_id human_handoff vip
          turns last_user_msg_id last_assistant_msg_id
          location_id fulfillment address phone_verified language_locked
          commerce_state cart_items cart_subtotal_cents cart_currency last_quote
          active_case_id last_order_id return_window_open
          last_tool locked_agent locked_until
          updated_at
        ]
        expect(defaults.keys).to match_array(expected_keys)
      end

      it "has proper array types" do
        expect(defaults["turns"]).to eq([])
        expect(defaults["cart_items"]).to eq([])
      end
    end
  end

  describe ".blank" do
    it "returns a hash" do
      expect(described_class.blank).to be_a(Hash)
    end

    it "returns a deep copy of DEFAULTS" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      expect(blank1.object_id).not_to eq(blank2.object_id)
      expect(blank1["turns"].object_id).not_to eq(blank2["turns"].object_id)
    end

    it "creates independent copies" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      blank1["tenant_id"] = "t1"
      blank1["turns"] << { "role" => "user" }

      expect(blank2["tenant_id"]).to be_nil
      expect(blank2["turns"]).to be_empty
      expect(blank2["cart_items"]).to be_empty
    end

    it "creates new object IDs for arrays" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      expect(blank1["turns"].object_id).not_to eq(blank2["turns"].object_id)
      expect(blank1["cart_items"].object_id).not_to eq(blank2["cart_items"].object_id)
    end
  end

  describe "immutability" do
    it "DEFAULTS is frozen" do
      expect { described_class::DEFAULTS["new_key"] = "value" }.to raise_error(FrozenError)
    end

    it "DEFAULTS nested structures are protected via .blank copies" do
      blank = described_class.blank
      blank["turns"] << { "role" => "user" }

      expect(described_class::DEFAULTS["turns"]).to be_empty
    end
  end

  describe "type safety" do
    it "ensures arrays are actual arrays" do
      blank = described_class.blank
      expect(blank["turns"]).to be_an(Array)
      expect(blank["cart_items"]).to be_an(Array)
    end

    it "ensures booleans are actual booleans" do
      blank = described_class.blank
      expect(blank["human_handoff"]).to be_in([ true, false ])
      expect(blank["vip"]).to be_in([ true, false ])
      expect(blank["phone_verified"]).to be_in([ true, false ])
      expect(blank["language_locked"]).to be_in([ true, false ])
    end

    it "ensures strings have correct types" do
      blank = described_class.blank
      expect(blank["locale"]).to be_a(String)
      expect(blank["timezone"]).to be_a(String)
      expect(blank["current_lane"]).to be_a(String)
      expect(blank["commerce_state"]).to be_a(String)
      expect(blank["cart_currency"]).to be_a(String)
    end

    it "ensures integers have correct types" do
      blank = described_class.blank
      expect(blank["cart_subtotal_cents"]).to be_a(Integer)
    end
  end
end
