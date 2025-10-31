# frozen_string_literal: true

require "rails_helper"

RSpec.describe State::Accessors::CartAccessor do
  let(:initial_state) do
    {
      "commerce" => {
        "cart" => {
          "items" => [],
          "subtotal_cents" => 0
        }
      }
    }
  end

  let(:accessor) { described_class.new(initial_state) }

  let(:product_info) do
    {
      name: "Pizza Margherita",
      price_cents: 12000
    }
  end

  describe "#initialize" do
    it "ensures cart is initialized in state" do
      empty_state = {}
      accessor = described_class.new(empty_state)

      expect(empty_state["commerce"]).to be_present
      expect(empty_state["commerce"]["cart"]).to eq({ "items" => [], "subtotal_cents" => 0 })
    end
  end

  describe "#add_item" do
    it "adds new item to cart" do
      patch = accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )

      expect(patch).to be_a(Hash)
      expect(patch.dig("commerce", "cart", "items")).to be_an(Array)
      expect(patch.dig("commerce", "cart", "items").size).to eq(1)
      expect(patch.dig("commerce", "cart", "subtotal_cents")).to eq(24000)
    end

    it "updates quantity when adding existing item" do
      # Add item first time
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )

      # Add same item again
      patch = accessor.add_item(
        product_id: "prod_001",
        quantity: 3,
        product_info: product_info
      )

      items = patch.dig("commerce", "cart", "items")
      expect(items.size).to eq(1)
      expect(items.first["quantity"]).to eq(5)
      expect(patch.dig("commerce", "cart", "subtotal_cents")).to eq(60000)
    end

    it "applies patch to internal state immediately" do
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )

      # Summary should reflect the added item immediately
      summary = accessor.summary
      expect(summary[:item_count]).to eq(2)
      expect(summary[:is_empty]).to be(false)
      expect(summary[:subtotal]).to eq("$120")
      expect(summary[:items].size).to eq(1)
    end
  end

  describe "#remove_item" do
    before do
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )
    end

    it "removes item from cart" do
      patch = accessor.remove_item(product_id: "prod_001")

      expect(patch.dig("commerce", "cart", "items")).to be_empty
      expect(patch.dig("commerce", "cart", "subtotal_cents")).to eq(0)
    end

    it "applies patch to internal state immediately" do
      accessor.remove_item(product_id: "prod_001")

      # Summary should reflect the removed item immediately
      summary = accessor.summary
      expect(summary[:item_count]).to eq(0)
      expect(summary[:is_empty]).to be(true)
      expect(summary[:subtotal]).to eq("$0")
      expect(summary[:items]).to be_empty
    end
  end

  describe "#update_quantity" do
    before do
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )
    end

    it "updates item quantity" do
      patch = accessor.update_quantity(product_id: "prod_001", quantity: 5)

      items = patch.dig("commerce", "cart", "items")
      expect(items.first["quantity"]).to eq(5)
      expect(patch.dig("commerce", "cart", "subtotal_cents")).to eq(60000)
    end

    it "removes item when quantity is zero" do
      patch = accessor.update_quantity(product_id: "prod_001", quantity: 0)

      expect(patch.dig("commerce", "cart", "items")).to be_empty
      expect(patch.dig("commerce", "cart", "subtotal_cents")).to eq(0)
    end

    it "applies patch to internal state immediately" do
      accessor.update_quantity(product_id: "prod_001", quantity: 5)

      # Summary should reflect the updated quantity immediately
      summary = accessor.summary
      expect(summary[:item_count]).to eq(5)
      expect(summary[:subtotal]).to eq("$600")
    end

    it "returns error for non-existent item" do
      result = accessor.update_quantity(product_id: "prod_999", quantity: 5)

      expect(result).to have_key(:error)
      expect(result[:error]).to include("not found")
    end
  end

  describe "#clear" do
    before do
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )
    end

    it "clears all items from cart" do
      patch = accessor.clear

      expect(patch.dig("commerce", "cart", "items")).to be_empty
      expect(patch.dig("commerce", "cart", "subtotal_cents")).to eq(0)
      expect(patch.dig("commerce", "state")).to eq("browsing")
    end

    it "applies patch to internal state immediately" do
      accessor.clear

      # Summary should reflect the cleared cart immediately
      summary = accessor.summary
      expect(summary[:item_count]).to eq(0)
      expect(summary[:is_empty]).to be(true)
      expect(summary[:subtotal]).to eq("$0")
      expect(summary[:items]).to be_empty
    end
  end

  describe "#summary" do
    it "returns empty cart summary when cart is empty" do
      summary = accessor.summary

      expect(summary[:item_count]).to eq(0)
      expect(summary[:is_empty]).to be(true)
      expect(summary[:subtotal]).to eq("$0")
      expect(summary[:items]).to be_empty
    end

    it "returns cart summary with items" do
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )

      summary = accessor.summary

      expect(summary[:item_count]).to eq(2)
      expect(summary[:is_empty]).to be(false)
      expect(summary[:subtotal]).to eq("$120")
      expect(summary[:items].size).to eq(1)
      expect(summary[:items].first).to include(
        name: "Pizza Margherita",
        quantity: 2,
        price: "$120",
        subtotal: "$240"
      )
    end

    it "reflects multiple operations correctly" do
      # Add first item
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )

      # Add second item
      accessor.add_item(
        product_id: "prod_002",
        quantity: 1,
        product_info: { name: "Pizza Pepperoni", price_cents: 14000 }
      )

      # Update first item quantity
      accessor.update_quantity(product_id: "prod_001", quantity: 3)

      # Verify summary reflects all changes
      summary = accessor.summary
      expect(summary[:item_count]).to eq(4)  # 3 + 1
      expect(summary[:subtotal]).to eq("$500")  # $360 + $140
      expect(summary[:items].size).to eq(2)
    end
  end

  describe "state consistency after operations" do
    it "maintains consistency across add, update, and remove operations" do
      # Add item
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )
      expect(accessor.item_count).to eq(2)

      # Update quantity
      accessor.update_quantity(product_id: "prod_001", quantity: 5)
      expect(accessor.item_count).to eq(5)
      expect(accessor.subtotal).to eq(60000)

      # Remove item
      accessor.remove_item(product_id: "prod_001")
      expect(accessor.item_count).to eq(0)
      expect(accessor.subtotal).to eq(0)
      expect(accessor.empty?).to be(true)
    end

    it "ensures summary always reflects the latest state" do
      # This is the key test for the bug fix
      # Before the fix, summary would show stale data

      # Initial state - empty cart
      expect(accessor.summary[:is_empty]).to be(true)

      # Add item - summary should immediately show it
      accessor.add_item(
        product_id: "prod_001",
        quantity: 2,
        product_info: product_info
      )
      summary_after_add = accessor.summary
      expect(summary_after_add[:is_empty]).to be(false)
      expect(summary_after_add[:item_count]).to eq(2)

      # Remove item - summary should immediately show empty
      accessor.remove_item(product_id: "prod_001")
      summary_after_remove = accessor.summary
      expect(summary_after_remove[:is_empty]).to be(true)
      expect(summary_after_remove[:item_count]).to eq(0)
    end
  end
end
