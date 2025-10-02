# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Upcaster do
  let(:upcaster) { described_class.new }

  # Helper to add migration methods dynamically for testing
  def add_migration(from_version, to_version, &block)
    method_name = "v#{from_version}_to_v#{to_version}"
    upcaster.define_singleton_method(method_name, &block)
  end

  describe "#call" do
    context "with current version state" do
      let(:current_state) do
        {
          "meta" => { "tenant_id" => "t1", "wa_id" => "wa1" },
          "dialogue" => { "turns" => [] },
          "version" => State::Contract::CURRENT_VERSION
        }
      end

      it "returns state unchanged" do
        result = upcaster.call(current_state)
        expect(result).to eq(current_state)
      end

      it "does not modify version" do
        original_version = current_state["version"]
        upcaster.call(current_state)
        expect(current_state["version"]).to eq(original_version)
      end

      it "does not trigger migrations" do
        # Since current version is 3, the loop condition fails immediately
        original_state = current_state.dup
        result = upcaster.call(current_state)
        expect(result).to eq(original_state)
      end
    end

    context "with missing version field" do
      let(:state_without_version) do
        {
          "meta" => { "tenant_id" => "t1" },
          "dialogue" => { "turns" => [] }
        }
      end

      it "treats missing version as 0 and raises NoMethodError" do
        expect {
          upcaster.call(state_without_version)
        }.to raise_error(NoMethodError, /undefined method/)
      end

      it "converts nil version to 0 and raises NoMethodError" do
        state = { "version" => nil }
        expect {
          upcaster.call(state)
        }.to raise_error(NoMethodError, /undefined method/)
      end
    end

    context "with version as string" do
      let(:string_version_state) do
        {
          "meta" => { "tenant_id" => "t1" },
          "version" => "1"
        }
      end

      it "converts string version to integer" do
        add_migration(1, 2) { |state| state }
        add_migration(2, 3) { |state| state }

        result = upcaster.call(string_version_state)
        expect(result["version"]).to eq(3)
      end
    end

    context "with old version requiring single migration" do
      let(:v2_state) do
        {
          "meta" => { "tenant_id" => "t1", "wa_id" => "wa1" },
          "dialogue" => { "turns" => [] },
          "commerce" => { "cart" => { "items" => [] } },
          "version" => 2
        }
      end

      before do
        add_migration(2, 3) do |state|
          state["support"] = { "active_case_id" => nil }
          state["migrated_to_v3"] = true
          state
        end
      end

      it "increments version to current" do
        result = upcaster.call(v2_state)
        expect(result["version"]).to eq(3)
      end

      it "applies migration changes" do
        result = upcaster.call(v2_state)
        expect(result["migrated_to_v3"]).to be true
        expect(result["support"]).to eq({ "active_case_id" => nil })
      end

      it "preserves existing state" do
        result = upcaster.call(v2_state)
        expect(result["meta"]["tenant_id"]).to eq("t1")
        expect(result["dialogue"]["turns"]).to eq([])
      end
    end

    context "with old version requiring multiple migrations" do
      let(:v1_state) do
        {
          "meta" => { "tenant_id" => "t1" },
          "slots" => { "cart" => { "items" => [ { "id" => 1 } ] } },
          "version" => 1
        }
      end

      before do
        # v1 -> v2: moves cart from slots to commerce
        add_migration(1, 2) do |state|
          if state.dig("slots", "cart")
            state["commerce"] ||= {}
            state["commerce"]["cart"] = state["slots"].delete("cart")
          end
          state["migrated_to_v2"] = true
          state
        end

        # v2 -> v3: adds support section
        add_migration(2, 3) do |state|
          state["support"] = { "active_case_id" => nil }
          state["migrated_to_v3"] = true
          state
        end
      end

      it "increments version through all migrations" do
        result = upcaster.call(v1_state)
        expect(result["version"]).to eq(3)
      end

      it "applies all migration changes" do
        result = upcaster.call(v1_state)
        expect(result["migrated_to_v2"]).to be true
        expect(result["migrated_to_v3"]).to be true
        expect(result["commerce"]["cart"]).to eq({ "items" => [ { "id" => 1 } ] })
        expect(result["support"]).to eq({ "active_case_id" => nil })
      end

      it "removes migrated fields" do
        result = upcaster.call(v1_state)
        expect(result["slots"]).not_to have_key("cart")
      end

      it "applies migrations in sequence" do
        call_order = []

        add_migration(1, 2) do |state|
          call_order << :v1_to_v2
          state["commerce"] = { "cart" => state["slots"].delete("cart") } if state.dig("slots", "cart")
          state
        end

        add_migration(2, 3) do |state|
          call_order << :v2_to_v3
          state["support"] = { "active_case_id" => nil }
          state
        end

        upcaster.call(v1_state)
        expect(call_order).to eq([:v1_to_v2, :v2_to_v3])
      end
    end

    context "with version 0 requiring all migrations" do
      let(:v0_state) do
        {
          "meta" => { "tenant_id" => "t1" },
          "version" => 0
        }
      end

      before do
        add_migration(0, 1) { |state| state["migrated_to_v1"] = true; state }
        add_migration(1, 2) { |state| state["migrated_to_v2"] = true; state }
        add_migration(2, 3) { |state| state["migrated_to_v3"] = true; state }
      end

      it "applies all migrations in sequence" do
        result = upcaster.call(v0_state)
        expect(result["migrated_to_v1"]).to be true
        expect(result["migrated_to_v2"]).to be true
        expect(result["migrated_to_v3"]).to be true
      end

      it "reaches current version" do
        result = upcaster.call(v0_state)
        expect(result["version"]).to eq(3)
      end
    end

    context "with example migration v1_to_v2 (cart relocation)" do
      let(:v1_state_with_cart_in_slots) do
        {
          "meta" => { "tenant_id" => "t1" },
          "slots" => {
            "location_id" => "loc123",
            "cart" => {
              "items" => [ { "id" => "item1", "qty" => 2 } ],
              "subtotal" => 1000
            }
          },
          "version" => 1
        }
      end

      before do
        add_migration(1, 2) do |state|
          if state.dig("slots", "cart")
            state["commerce"] ||= {}
            state["commerce"]["cart"] = state["slots"].delete("cart")
          end
          state
        end

        add_migration(2, 3) { |state| state }
      end

      it "moves cart from slots to commerce" do
        result = upcaster.call(v1_state_with_cart_in_slots)

        expect(result["commerce"]["cart"]).to eq({
          "items" => [ { "id" => "item1", "qty" => 2 } ],
          "subtotal" => 1000
        })
        expect(result["slots"]).not_to have_key("cart")
      end

      it "preserves other slots fields" do
        result = upcaster.call(v1_state_with_cart_in_slots)
        expect(result["slots"]["location_id"]).to eq("loc123")
      end

      it "creates commerce section if it doesn't exist" do
        result = upcaster.call(v1_state_with_cart_in_slots)
        expect(result).to have_key("commerce")
      end
    end

    context "with example migration v2_to_v3 (support section and last_tool restructure)" do
      let(:v2_state_with_string_last_tool) do
        {
          "meta" => { "tenant_id" => "t1" },
          "last_tool" => "search_products",
          "version" => 2
        }
      end

      before do
        add_migration(2, 3) do |state|
          state["support"] ||= {
            "active_case_id" => nil,
            "last_order_id" => nil,
            "return_window_open" => nil
          }

          if state["last_tool"].is_a?(String)
            state["last_tool"] = {
              "name" => state["last_tool"],
              "ok" => true,
              "at" => "2025-01-01T00:00:00Z"
            }
          end
          state
        end
      end

      it "adds support section" do
        result = upcaster.call(v2_state_with_string_last_tool)

        expect(result["support"]).to eq({
          "active_case_id" => nil,
          "last_order_id" => nil,
          "return_window_open" => nil
        })
      end

      it "converts string last_tool to hash" do
        result = upcaster.call(v2_state_with_string_last_tool)

        expect(result["last_tool"]).to be_a(Hash)
        expect(result["last_tool"]["name"]).to eq("search_products")
        expect(result["last_tool"]["ok"]).to be true
        expect(result["last_tool"]).to have_key("at")
      end

      it "preserves existing meta" do
        result = upcaster.call(v2_state_with_string_last_tool)
        expect(result["meta"]["tenant_id"]).to eq("t1")
      end
    end

    context "edge cases" do
      it "handles empty state at current version" do
        state = { "version" => State::Contract::CURRENT_VERSION }
        result = upcaster.call(state)
        expect(result["version"]).to eq(State::Contract::CURRENT_VERSION)
      end

      it "handles state with extra fields" do
        state = {
          "meta" => { "tenant_id" => "t1" },
          "custom_field" => "custom_value",
          "nested" => { "data" => "value" },
          "version" => State::Contract::CURRENT_VERSION
        }

        result = upcaster.call(state)
        expect(result["custom_field"]).to eq("custom_value")
        expect(result["nested"]["data"]).to eq("value")
      end

      it "preserves state mutations during migrations" do
        state = {
          "meta" => { "tenant_id" => "t1" },
          "data" => { "value" => "original" },
          "version" => 1
        }

        add_migration(1, 2) do |s|
          s["data"]["value"] = "modified_v2"
          s["added_in_v2"] = true
          s
        end

        add_migration(2, 3) do |s|
          s["data"]["value"] = "modified_v3"
          s["added_in_v3"] = true
          s
        end

        result = upcaster.call(state)
        expect(result["data"]["value"]).to eq("modified_v3")
        expect(result["added_in_v2"]).to be true
        expect(result["added_in_v3"]).to be true
      end
    end

    context "error handling" do
      it "raises NoMethodError when migration method is missing" do
        state = { "version" => 1 }

        expect {
          upcaster.call(state)
        }.to raise_error(NoMethodError, /undefined method/)
      end

      it "propagates errors from migration methods" do
        state = { "version" => 2 }

        add_migration(2, 3) do |_state|
          raise RuntimeError, "Migration failed"
        end

        expect {
          upcaster.call(state)
        }.to raise_error(RuntimeError, "Migration failed")
      end
    end

    context "state mutation" do
      it "mutates the state object directly" do
        state = {
          "meta" => { "tenant_id" => "t1" },
          "version" => 2
        }

        add_migration(2, 3) do |s|
          s["support"] = { "active_case_id" => nil }
          s
        end

        original_object_id = state.object_id
        result = upcaster.call(state)

        # Result should be the same object (mutated)
        expect(result.object_id).to eq(original_object_id)
        expect(state["support"]).to eq({ "active_case_id" => nil })
      end
    end

    context "version tracking" do
      it "updates version after each migration" do
        versions_seen = []
        state = { "version" => 1 }

        add_migration(1, 2) do |s|
          versions_seen << s["version"]
          s
        end

        add_migration(2, 3) do |s|
          versions_seen << s["version"]
          s
        end

        upcaster.call(state)

        # Version should be updated between migrations
        expect(versions_seen).to eq([1, 2])
      end

      it "sets version before calling next migration" do
        state = { "version" => 1 }

        add_migration(1, 2) do |s|
          s["v1_to_v2_version"] = s["version"]
          s
        end

        add_migration(2, 3) do |s|
          s["v2_to_v3_version"] = s["version"]
          s
        end

        result = upcaster.call(state)

        # v1_to_v2 should see version 1
        expect(result["v1_to_v2_version"]).to eq(1)
        # v2_to_v3 should see version 2 (already incremented)
        expect(result["v2_to_v3_version"]).to eq(2)
      end

      it "increments version by 1 for each migration" do
        state = { "version" => 0 }

        add_migration(0, 1) { |s| s }
        add_migration(1, 2) { |s| s }
        add_migration(2, 3) { |s| s }

        result = upcaster.call(state)
        expect(result["version"]).to eq(3)
      end
    end

    context "complex migration chains" do
      it "handles state transformations across multiple versions" do
        # Start with v1 format
        state = {
          "meta" => { "tenant_id" => "t1" },
          "slots" => {
            "cart" => { "items" => [ { "id" => 1 } ] }
          },
          "last_tool" => "search",
          "version" => 1
        }

        # v1 -> v2: Move cart
        add_migration(1, 2) do |s|
          if s.dig("slots", "cart")
            s["commerce"] = { "cart" => s["slots"].delete("cart") }
          end
          s
        end

        # v2 -> v3: Add support, restructure last_tool
        add_migration(2, 3) do |s|
          s["support"] = { "active_case_id" => nil }
          if s["last_tool"].is_a?(String)
            s["last_tool"] = { "name" => s["last_tool"] }
          end
          s
        end

        result = upcaster.call(state)

        # Verify all transformations applied
        expect(result["commerce"]["cart"]["items"]).to eq([ { "id" => 1 } ])
        expect(result["slots"]).not_to have_key("cart")
        expect(result["support"]["active_case_id"]).to be_nil
        expect(result["last_tool"]).to eq({ "name" => "search" })
        expect(result["version"]).to eq(3)
      end

      it "maintains referential integrity across migrations" do
        state = {
          "user" => { "id" => "u1", "cart_id" => "cart123" },
          "carts" => { "cart123" => { "items" => [] } },
          "version" => 1
        }

        add_migration(1, 2) do |s|
          # Restructure but maintain references
          s["commerce"] = { "carts" => s.delete("carts") }
          s
        end

        add_migration(2, 3) do |s|
          # Verify reference still valid
          cart_id = s["user"]["cart_id"]
          s["reference_valid"] = s.dig("commerce", "carts", cart_id).present?
          s
        end

        result = upcaster.call(state)
        expect(result["reference_valid"]).to be true
      end
    end

    context "migration method naming" do
      it "follows vX_to_vY naming convention" do
        state = { "version" => 1 }

        # Test that the dynamic method dispatch works
        add_migration(1, 2) { |s| s["reached_v2"] = true; s }
        add_migration(2, 3) { |s| s["reached_v3"] = true; s }

        result = upcaster.call(state)

        expect(result["reached_v2"]).to be true
        expect(result["reached_v3"]).to be true
      end
    end
  end
end
