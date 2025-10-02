# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Patcher do
  let(:redis) { Redis.new }
  let(:patcher) { described_class.new(redis) }
  let(:key) { "session:test_user" }

  before do
    # Clean up Redis before each test
    redis.del(key)
  end

  after do
    # Clean up Redis after each test
    redis.del(key)
  end

  describe "#initialize" do
    it "accepts a redis connection" do
      expect { described_class.new(redis) }.not_to raise_error
    end

    it "stores the redis connection" do
      patcher = described_class.new(redis)
      expect(patcher.instance_variable_get(:@r)).to eq(redis)
    end
  end

  describe "#patch!" do
    context "with successful patch" do
      let(:initial_state) do
        {
          "meta" => {
            "tenant_id" => "tenant_123",
            "wa_id" => "16505551234",
            "locale" => "es-CO",
            "current_lane" => "info"
          },
          "dialogue" => {
            "turns" => [],
            "last_user_msg_id" => nil
          },
          "version" => 1
        }
      end

      let(:patch) do
        {
          "meta" => { "current_lane" => "commerce" },
          "dialogue" => { "last_user_msg_id" => "msg_456" }
        }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "returns true on successful patch" do
        result = patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        expect(result).to be true
      end

      it "merges patch into current state" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["meta"]["current_lane"]).to eq("commerce")
        expect(updated["dialogue"]["last_user_msg_id"]).to eq("msg_456")
      end

      it "preserves unpatched fields" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["meta"]["tenant_id"]).to eq("tenant_123")
        expect(updated["meta"]["wa_id"]).to eq("16505551234")
        expect(updated["meta"]["locale"]).to eq("es-CO")
      end

      it "increments version number" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["version"]).to eq(2)
      end

      it "sets TTL on the key" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch,
          ttl_seconds: 3600
        )

        ttl = redis.ttl(key)
        expect(ttl).to be > 0
        expect(ttl).to be <= 3600
      end

      it "uses default TTL of 86400 seconds (24 hours)" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        ttl = redis.ttl(key)
        expect(ttl).to be > 0
        expect(ttl).to be <= 86_400
      end

      it "deep merges nested hashes" do
        patch = {
          "meta" => {
            "flags" => { "vip" => true },
            "custom" => { "field" => "value" }
          }
        }

        initial = initial_state.merge(
          "meta" => initial_state["meta"].merge(
            "flags" => { "human_handoff" => false }
          )
        )
        redis.set(key, initial.to_json)

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["meta"]["flags"]["human_handoff"]).to be false
        expect(updated["meta"]["flags"]["vip"]).to be true
        expect(updated["meta"]["custom"]["field"]).to eq("value")
      end

      it "replaces arrays rather than merging" do
        patch = {
          "dialogue" => {
            "turns" => [ { "role" => "user", "text" => "new" } ]
          }
        }

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["dialogue"]["turns"]).to eq([ { "role" => "user", "text" => "new" } ])
      end

      it "replaces scalar values" do
        patch = {
          "meta" => { "locale" => "en-US" }
        }

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["meta"]["locale"]).to eq("en-US")
      end
    end

    context "with version conflict" do
      let(:initial_state) do
        {
          "meta" => { "tenant_id" => "t1" },
          "version" => 5
        }
      end

      let(:patch) do
        { "meta" => { "locale" => "en-US" } }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "returns false when version conflicts" do
        result = patcher.patch!(
          key: key,
          expected_version: 3, # Expected 3, but current is 5
          patch: patch
        )

        expect(result).to be false
      end

      it "does not modify state on version conflict" do
        original = redis.get(key)

        patcher.patch!(
          key: key,
          expected_version: 3,
          patch: patch
        )

        expect(redis.get(key)).to eq(original)
      end

      it "does not increment version on conflict" do
        patcher.patch!(
          key: key,
          expected_version: 3,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["version"]).to eq(5)
      end
    end

    context "with non-existent key" do
      let(:patch) do
        { "meta" => { "tenant_id" => "new_tenant" } }
      end

      it "creates new state from empty object" do
        result = patcher.patch!(
          key: "session:nonexistent",
          expected_version: 0,
          patch: patch
        )

        expect(result).to be true
      end

      it "sets patched values" do
        patcher.patch!(
          key: "session:nonexistent",
          expected_version: 0,
          patch: patch
        )

        state = JSON.parse(redis.get("session:nonexistent"))
        expect(state["meta"]["tenant_id"]).to eq("new_tenant")
        expect(state["version"]).to eq(1)
      end

      after do
        redis.del("session:nonexistent")
      end
    end

    context "with missing version in current state" do
      let(:initial_state) do
        { "meta" => { "tenant_id" => "t1" } }
      end

      let(:patch) do
        { "meta" => { "locale" => "en-US" } }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "treats missing version as 0" do
        result = patcher.patch!(
          key: key,
          expected_version: 0,
          patch: patch
        )

        expect(result).to be true
      end

      it "sets version to 1 after patch" do
        patcher.patch!(
          key: key,
          expected_version: 0,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["version"]).to eq(1)
      end
    end

    context "with Redis errors" do
      it "returns false on Redis::BaseError" do
        allow(redis).to receive(:watch).and_raise(Redis::BaseError)

        result = patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => {} }
        )

        expect(result).to be false
      end

      it "calls unwatch in ensure block" do
        allow(redis).to receive(:watch).and_raise(Redis::BaseError)
        expect(redis).to receive(:unwatch)

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => {} }
        )
      end
    end

    context "with concurrent modifications" do
      let(:initial_state) do
        {
          "meta" => { "tenant_id" => "t1", "locale" => "es-CO" },
          "version" => 1
        }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "handles optimistic locking correctly" do
        # Simulate concurrent modification by changing state between watch and multi
        allow(redis).to receive(:watch).and_wrap_original do |method, *args, &block|
          method.call(*args) do
            # Modify state during transaction
            concurrent_state = JSON.parse(redis.get(key))
            concurrent_state["meta"]["locale"] = "en-US"
            concurrent_state["version"] = 2
            redis.set(key, concurrent_state.to_json)

            block.call
          end
        end

        result = patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => { "current_lane" => "commerce" } }
        )

        # Should fail due to concurrent modification
        expect(result).to be false
      end
    end

    context "with complex nested structures" do
      let(:initial_state) do
        {
          "meta" => {
            "tenant_id" => "t1",
            "flags" => {
              "human_handoff" => false,
              "vip" => false
            },
            "custom" => {
              "level1" => {
                "level2" => {
                  "value" => "original"
                }
              }
            }
          },
          "commerce" => {
            "cart" => {
              "items" => [ { "id" => 1, "qty" => 2 } ],
              "subtotal_cents" => 1000
            }
          },
          "version" => 1
        }
      end

      it "deep merges multiple levels" do
        patch = {
          "meta" => {
            "flags" => { "vip" => true },
            "custom" => {
              "level1" => {
                "level2" => {
                  "new_field" => "added"
                }
              }
            }
          },
          "commerce" => {
            "cart" => {
              "currency" => "USD"
            }
          }
        }

        redis.set(key, initial_state.to_json)

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))

        # Verify deep merge
        expect(updated["meta"]["flags"]["human_handoff"]).to be false
        expect(updated["meta"]["flags"]["vip"]).to be true
        expect(updated["meta"]["custom"]["level1"]["level2"]["value"]).to eq("original")
        expect(updated["meta"]["custom"]["level1"]["level2"]["new_field"]).to eq("added")
        expect(updated["commerce"]["cart"]["subtotal_cents"]).to eq(1000)
        expect(updated["commerce"]["cart"]["currency"]).to eq("USD")
      end

      it "replaces arrays in nested structures" do
        patch = {
          "commerce" => {
            "cart" => {
              "items" => [ { "id" => 2, "qty" => 5 } ]
            }
          }
        }

        redis.set(key, initial_state.to_json)

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["commerce"]["cart"]["items"]).to eq([ { "id" => 2, "qty" => 5 } ])
      end
    end

    context "with empty patch" do
      let(:initial_state) do
        {
          "meta" => { "tenant_id" => "t1" },
          "version" => 1
        }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "increments version even with empty patch" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: {}
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["version"]).to eq(2)
      end

      it "preserves all state with empty patch" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: {}
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["meta"]["tenant_id"]).to eq("t1")
      end
    end

    context "with nil values in patch" do
      let(:initial_state) do
        {
          "meta" => { "tenant_id" => "t1", "customer_id" => "c123" },
          "version" => 1
        }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "sets nil values explicitly" do
        patch = {
          "meta" => { "customer_id" => nil }
        }

        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: patch
        )

        updated = JSON.parse(redis.get(key))
        expect(updated["meta"]["customer_id"]).to be_nil
      end
    end

    context "with custom TTL values" do
      let(:initial_state) do
        { "meta" => { "tenant_id" => "t1" }, "version" => 1 }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "respects short TTL" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => { "locale" => "en-US" } },
          ttl_seconds: 60
        )

        ttl = redis.ttl(key)
        expect(ttl).to be > 0
        expect(ttl).to be <= 60
      end

      it "respects long TTL" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => { "locale" => "en-US" } },
          ttl_seconds: 604_800 # 1 week
        )

        ttl = redis.ttl(key)
        expect(ttl).to be > 86_400 # Greater than 1 day
        expect(ttl).to be <= 604_800
      end
    end

    context "with sequential patches" do
      let(:initial_state) do
        {
          "meta" => { "tenant_id" => "t1", "current_lane" => "info" },
          "version" => 1
        }
      end

      before do
        redis.set(key, initial_state.to_json)
      end

      it "allows sequential patches with correct version tracking" do
        # First patch
        result1 = patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => { "current_lane" => "commerce" } }
        )
        expect(result1).to be true

        # Second patch
        result2 = patcher.patch!(
          key: key,
          expected_version: 2,
          patch: { "meta" => { "current_lane" => "support" } }
        )
        expect(result2).to be true

        # Third patch
        result3 = patcher.patch!(
          key: key,
          expected_version: 3,
          patch: { "meta" => { "current_lane" => "info" } }
        )
        expect(result3).to be true

        updated = JSON.parse(redis.get(key))
        expect(updated["version"]).to eq(4)
        expect(updated["meta"]["current_lane"]).to eq("info")
      end

      it "fails if version is not sequential" do
        patcher.patch!(
          key: key,
          expected_version: 1,
          patch: { "meta" => { "current_lane" => "commerce" } }
        )

        # Try to patch with old version
        result = patcher.patch!(
          key: key,
          expected_version: 1, # Should be 2
          patch: { "meta" => { "current_lane" => "support" } }
        )

        expect(result).to be false
      end
    end
  end

  describe "atomic operations" do
    let(:initial_state) do
      { "meta" => { "counter" => 0 }, "version" => 1 }
    end

    before do
      redis.set(key, initial_state.to_json)
    end

    it "ensures atomicity of watch-multi-exec" do
      # This test verifies the atomic nature of Redis transactions
      expect(redis).to receive(:watch).with(key).and_call_original
      expect(redis).to receive(:multi).and_call_original
      expect(redis).to receive(:unwatch).and_call_original

      patcher.patch!(
        key: key,
        expected_version: 1,
        patch: { "meta" => { "counter" => 1 } }
      )
    end
  end

  describe "error recovery" do
    it "calls unwatch even when RuntimeError is raised" do
      allow(redis).to receive(:get).and_raise(RuntimeError, "Test error")
      expect(redis).to receive(:unwatch).at_least(:once)

      result = patcher.patch!(
        key: key,
        expected_version: 1,
        patch: {}
      )

      expect(result).to be false
    end

    it "calls unwatch even when Redis::BaseError is raised" do
      allow(redis).to receive(:get).and_raise(Redis::BaseError)
      expect(redis).to receive(:unwatch).at_least(:once)

      result = patcher.patch!(
        key: key,
        expected_version: 1,
        patch: {}
      )

      expect(result).to be false
    end
  end
end
