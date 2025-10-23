# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Contract do
  describe "constants" do
    describe "REQUIRED_KEYS" do
      it "is frozen" do
        expect(described_class::REQUIRED_KEYS).to be_frozen
      end

      it "contains essential structural keys" do
        expect(described_class::REQUIRED_KEYS).to eq(%w[meta dialogue slots])
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

    describe "meta section" do
      let(:meta) { defaults["meta"] }

      it "exists" do
        expect(meta).to be_a(Hash)
      end

      it "has tenant_id field" do
        expect(meta).to have_key("tenant_id")
        expect(meta["tenant_id"]).to be_nil
      end

      it "has wa_id field" do
        expect(meta).to have_key("wa_id")
        expect(meta["wa_id"]).to be_nil
      end

      it "has locale field with default" do
        expect(meta["locale"]).to eq("es-CO")
      end

      it "has timezone field with default" do
        expect(meta["timezone"]).to eq("America/Bogota")
      end

      it "has current_lane field with default" do
        expect(meta["current_lane"]).to eq("info")
      end

      it "has sticky_until field" do
        expect(meta).to have_key("sticky_until")
        expect(meta["sticky_until"]).to be_nil
      end

      it "has customer_id field" do
        expect(meta).to have_key("customer_id")
        expect(meta["customer_id"]).to be_nil
      end

      it "has flags field with nested defaults" do
        expect(meta["flags"]).to be_a(Hash)
        expect(meta["flags"]["human_handoff"]).to be false
        expect(meta["flags"]["vip"]).to be false
      end

      it "has all expected keys" do
        expected_keys = %w[tenant_id wa_id locale timezone current_lane sticky_until customer_id flags]
        expect(meta.keys).to match_array(expected_keys)
      end
    end

    describe "dialogue section" do
      let(:dialogue) { defaults["dialogue"] }

      it "exists" do
        expect(dialogue).to be_a(Hash)
      end

      it "has turns field as empty array" do
        expect(dialogue["turns"]).to eq([])
      end

      it "has last_user_msg_id field" do
        expect(dialogue).to have_key("last_user_msg_id")
        expect(dialogue["last_user_msg_id"]).to be_nil
      end

      it "has last_assistant_msg_id field" do
        expect(dialogue).to have_key("last_assistant_msg_id")
        expect(dialogue["last_assistant_msg_id"]).to be_nil
      end

      it "has all expected keys" do
        expected_keys = %w[turns last_user_msg_id last_assistant_msg_id]
        expect(dialogue.keys).to match_array(expected_keys)
      end
    end

    describe "slots section" do
      let(:slots) { defaults["slots"] }

      it "exists" do
        expect(slots).to be_a(Hash)
      end

      it "has location_id field" do
        expect(slots).to have_key("location_id")
        expect(slots["location_id"]).to be_nil
      end

      it "has fulfillment field" do
        expect(slots).to have_key("fulfillment")
        expect(slots["fulfillment"]).to be_nil
      end

      it "has address field" do
        expect(slots).to have_key("address")
        expect(slots["address"]).to be_nil
      end

      it "has phone_verified field" do
        expect(slots["phone_verified"]).to be false
      end

      it "has language_locked field" do
        expect(slots["language_locked"]).to be false
      end

      it "has all expected keys" do
        expected_keys = %w[location_id fulfillment address phone_verified language_locked]
        expect(slots.keys).to match_array(expected_keys)
      end
    end

    describe "commerce section" do
      let(:commerce) { defaults["commerce"] }

      it "exists" do
        expect(commerce).to be_a(Hash)
      end

      it "has state field with default" do
        expect(commerce["state"]).to eq("browsing")
      end

      it "has cart field as nested hash" do
        expect(commerce["cart"]).to be_a(Hash)
        expect(commerce["cart"]["items"]).to eq([])
        expect(commerce["cart"]["subtotal_cents"]).to eq(0)
        expect(commerce["cart"]["currency"]).to eq("COP")
      end

      it "has last_quote field" do
        expect(commerce).to have_key("last_quote")
        expect(commerce["last_quote"]).to be_nil
      end

      it "has all expected keys" do
        expected_keys = %w[state cart last_quote]
        expect(commerce.keys).to match_array(expected_keys)
      end
    end

    describe "support section" do
      let(:support) { defaults["support"] }

      it "exists" do
        expect(support).to be_a(Hash)
      end

      it "has active_case_id field" do
        expect(support).to have_key("active_case_id")
        expect(support["active_case_id"]).to be_nil
      end

      it "has last_order_id field" do
        expect(support).to have_key("last_order_id")
        expect(support["last_order_id"]).to be_nil
      end

      it "has return_window_open field" do
        expect(support).to have_key("return_window_open")
        expect(support["return_window_open"]).to be_nil
      end

      it "has all expected keys" do
        expected_keys = %w[active_case_id last_order_id return_window_open]
        expect(support.keys).to match_array(expected_keys)
      end
    end

    describe "top-level fields" do
      it "has last_tool field" do
        expect(defaults).to have_key("last_tool")
        expect(defaults["last_tool"]).to be_nil
      end

      it "has locks field" do
        expect(defaults["locks"]).to be_a(Hash)
        expect(defaults["locks"]["agent"]).to be_nil
        expect(defaults["locks"]["until"]).to be_nil
      end
    end

    describe "complete structure validation" do
      it "has all expected top-level keys" do
        expected_keys = %w[meta dialogue slots commerce support last_tool locks]
        expect(defaults.keys).to match_array(expected_keys)
      end

      it "has proper nesting depth" do
        # Validate specific nested paths exist
        expect(defaults.dig("meta", "flags", "human_handoff")).to be false
        expect(defaults.dig("commerce", "cart", "items")).to eq([])
        expect(defaults.dig("dialogue", "turns")).to eq([])
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

      expect(blank1).to eq(blank2)
      expect(blank1).not_to be(blank2)
    end

    it "creates independent copies" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      blank1["meta"]["tenant_id"] = "tenant_123"
      blank1["meta"]["flags"]["vip"] = true
      blank1["dialogue"]["turns"] << { "role" => "user", "text" => "hi" }
      blank1["commerce"]["cart"]["items"] << { "id" => "item1" }

      expect(blank2["meta"]["tenant_id"]).to be_nil
      expect(blank2["meta"]["flags"]["vip"]).to be false
      expect(blank2["dialogue"]["turns"]).to eq([])
      expect(blank2["commerce"]["cart"]["items"]).to eq([])
    end

    it "does not mutate DEFAULTS constant" do
      original_defaults = described_class::DEFAULTS.deep_dup

      blank = described_class.blank
      blank["meta"]["locale"] = "en-US"
      blank["meta"]["flags"]["human_handoff"] = true
      blank["dialogue"]["turns"] << { "role" => "assistant", "text" => "hello" }
      blank["commerce"]["state"] = "checkout"

      expect(described_class::DEFAULTS).to eq(original_defaults)
    end

    it "creates deeply independent nested structures" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      # Modify nested hash
      blank1["meta"]["flags"]["custom_flag"] = true

      expect(blank2["meta"]["flags"]).not_to have_key("custom_flag")
    end

    it "creates independent array copies" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      blank1["dialogue"]["turns"] << "turn1"
      blank1["commerce"]["cart"]["items"] << "item1"

      expect(blank2["dialogue"]["turns"]).to be_empty
      expect(blank2["commerce"]["cart"]["items"]).to be_empty
    end

    it "creates new object IDs for nested hashes" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      expect(blank1["meta"].object_id).not_to eq(blank2["meta"].object_id)
      expect(blank1["dialogue"].object_id).not_to eq(blank2["dialogue"].object_id)
      expect(blank1["commerce"]["cart"].object_id).not_to eq(blank2["commerce"]["cart"].object_id)
    end

    it "creates new object IDs for nested arrays" do
      blank1 = described_class.blank
      blank2 = described_class.blank

      expect(blank1["dialogue"]["turns"].object_id).not_to eq(blank2["dialogue"]["turns"].object_id)
      expect(blank1["commerce"]["cart"]["items"].object_id).not_to eq(blank2["commerce"]["cart"]["items"].object_id)
    end
  end

  describe "immutability" do
    it "DEFAULTS is frozen" do
      expect { described_class::DEFAULTS["new_key"] = "value" }.to raise_error(FrozenError)
    end

    it "DEFAULTS nested structures are protected via .blank copies" do
      # Marshal.load doesn't freeze nested structures, but .blank provides isolation
      blank1 = described_class.blank
      blank2 = described_class.blank

      blank1["meta"]["new_key"] = "value"
      blank1["dialogue"]["turns"] << "turn"

      # Verify isolation - blank2 should be unaffected
      expect(blank2["meta"]).not_to have_key("new_key")
      expect(blank2["dialogue"]["turns"]).to be_empty
    end

    it "REQUIRED_KEYS is frozen" do
      expect { described_class::REQUIRED_KEYS << "new_key" }.to raise_error(FrozenError)
    end
  end

  describe "thread safety" do
    it "returns independent blank copies across threads" do
      mutex = Mutex.new
      results = []
      threads = []

      10.times do |i|
        threads << Thread.new do
          blank = described_class.blank
          blank["meta"]["tenant_id"] = "tenant_#{i}"
          blank["dialogue"]["turns"] << { "id" => i }

          mutex.synchronize do
            results << {
              tenant: blank["meta"]["tenant_id"],
              turns_count: blank["dialogue"]["turns"].size
            }
          end
        end
      end

      threads.each(&:join)

      # Each thread should have its own isolated state
      expect(results.size).to eq(10)
      expect(results.map { |r| r[:tenant] }).to match_array(
        (0..9).map { |i| "tenant_#{i}" }
      )
      expect(results.map { |r| r[:turns_count] }).to all(eq(1))
    end
  end

  describe "backward compatibility" do
    it "maintains stable field names" do
      # These field names should never change to maintain compatibility
      stable_fields = {
        "meta" => %w[tenant_id wa_id locale timezone current_lane],
        "dialogue" => %w[turns],
        "slots" => %w[location_id fulfillment address],
        "commerce" => %w[state cart],
        "support" => %w[active_case_id]
      }

      stable_fields.each do |section, fields|
        fields.each do |field|
          expect(described_class::DEFAULTS[section]).to have_key(field),
            "Expected #{section}.#{field} to exist for backward compatibility"
        end
      end
    end

    it "maintains stable default values for critical fields" do
      blank = described_class.blank

      expect(blank["meta"]["locale"]).to eq("es-CO")
      expect(blank["meta"]["timezone"]).to eq("America/Bogota")
      expect(blank["meta"]["current_lane"]).to eq("info")
      expect(blank["commerce"]["state"]).to eq("browsing")
      expect(blank["commerce"]["cart"]["currency"]).to eq("COP")
    end
  end

  describe "data type consistency" do
    it "uses consistent types for similar fields" do
      blank = described_class.blank

      # All ID fields should be nil (not empty strings)
      expect(blank["meta"]["tenant_id"]).to be_nil
      expect(blank["meta"]["wa_id"]).to be_nil
      expect(blank["meta"]["customer_id"]).to be_nil
      expect(blank["slots"]["location_id"]).to be_nil
      expect(blank["support"]["active_case_id"]).to be_nil

      # Boolean fields should be false (not nil)
      expect(blank["meta"]["flags"]["human_handoff"]).to be false
      expect(blank["meta"]["flags"]["vip"]).to be false
      expect(blank["slots"]["phone_verified"]).to be false
      expect(blank["slots"]["language_locked"]).to be false

      # Array fields should be empty arrays (not nil)
      expect(blank["dialogue"]["turns"]).to eq([])
      expect(blank["commerce"]["cart"]["items"]).to eq([])
    end
  end
end
