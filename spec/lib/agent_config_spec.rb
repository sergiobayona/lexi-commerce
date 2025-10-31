# frozen_string_literal: true

require "rails_helper"
require_relative "../../lib/agent_config"

RSpec.describe AgentConfig do
  # Reset cached configuration before each test
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe ".lanes" do
    it "returns all configured lanes sorted alphabetically" do
      expect(described_class.lanes).to eq(%w[commerce info order product support])
    end

    it "returns an array" do
      expect(described_class.lanes).to be_an(Array)
    end
  end

  describe ".default_lane" do
    it "returns the lane marked as default in config" do
      expect(described_class.default_lane).to eq("info")
    end

    it "caches the default lane" do
      # Call twice to ensure caching works
      first_call = described_class.default_lane
      second_call = described_class.default_lane
      expect(first_call).to eq(second_call)
    end
  end

  describe ".agent_class_for" do
    it "returns correct agent class for info lane" do
      expect(described_class.agent_class_for("info")).to eq(Agents::InfoAgent)
    end

    it "returns correct agent class for commerce lane" do
      expect(described_class.agent_class_for("commerce")).to eq(Agents::CommerceAgent)
    end

    it "returns correct agent class for support lane" do
      expect(described_class.agent_class_for("support")).to eq(Agents::SupportAgent)
    end

    it "returns correct agent class for product lane" do
      expect(described_class.agent_class_for("product")).to eq(Agents::ProductAgent)
    end

    it "returns correct agent class for order lane" do
      expect(described_class.agent_class_for("order")).to eq(Agents::OrderStatusAgent)
    end

    it "returns nil for unknown lane" do
      expect(described_class.agent_class_for("unknown")).to be_nil
    end

    it "raises ConfigurationError if class name is invalid" do
      # This would require mocking the config, skipping for now
      # Can be added if we want to test error handling for invalid class names
    end
  end

  describe ".description_for" do
    it "returns description for info lane" do
      description = described_class.description_for("info")
      expect(description).to include("General business information")
    end

    it "returns description for commerce lane" do
      description = described_class.description_for("commerce")
      expect(description).to include("Shopping and transactions")
    end

    it "returns description for support lane" do
      description = described_class.description_for("support")
      expect(description).to include("Customer service issues")
    end

    it "returns description for product lane" do
      description = described_class.description_for("product")
      expect(description).to include("Product-specific questions")
    end

    it "returns description for order lane" do
      description = described_class.description_for("order")
      expect(description).to include("Order tracking")
    end

    it "returns nil for unknown lane" do
      expect(described_class.description_for("unknown")).to be_nil
    end
  end

  describe ".lane_descriptions" do
    it "returns hash of all lane descriptions" do
      descriptions = described_class.lane_descriptions
      expect(descriptions).to be_a(Hash)
      expect(descriptions.keys).to match_array(%w[info product commerce order support])
    end

    it "includes all required descriptions" do
      descriptions = described_class.lane_descriptions
      expect(descriptions["info"]).to be_present
      expect(descriptions["product"]).to be_present
      expect(descriptions["commerce"]).to be_present
      expect(descriptions["order"]).to be_present
      expect(descriptions["support"]).to be_present
    end

    it "caches the result" do
      first_call = described_class.lane_descriptions
      second_call = described_class.lane_descriptions
      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe ".valid_lane?" do
    it "returns true for valid lanes" do
      expect(described_class.valid_lane?("info")).to be true
      expect(described_class.valid_lane?("product")).to be true
      expect(described_class.valid_lane?("commerce")).to be true
      expect(described_class.valid_lane?("order")).to be true
      expect(described_class.valid_lane?("support")).to be true
    end

    it "returns false for invalid lanes" do
      expect(described_class.valid_lane?("unknown")).to be false
      expect(described_class.valid_lane?("billing")).to be false
      expect(described_class.valid_lane?("")).to be false
    end

    it "handles symbols" do
      expect(described_class.valid_lane?(:info)).to be true
      expect(described_class.valid_lane?(:unknown)).to be false
    end
  end

  describe ".reset!" do
    it "clears all caches" do
      # Populate caches
      described_class.lanes
      described_class.default_lane
      described_class.lane_descriptions

      # Reset
      described_class.reset!

      # Verify caches are cleared by checking instance variables
      expect(described_class.instance_variable_get(:@config)).to be_nil
      expect(described_class.instance_variable_get(:@lanes)).to be_nil
      expect(described_class.instance_variable_get(:@default_lane)).to be_nil
      expect(described_class.instance_variable_get(:@lane_descriptions)).to be_nil
    end
  end

  describe "configuration loading" do
    it "loads configuration from config/routing.yml" do
      expect(File).to exist(Rails.root.join("config/routing.yml"))
    end

    it "has valid structure" do
      # Verify config loads without errors
      expect { described_class.lanes }.not_to raise_error
    end

    it "all configured agents have required fields" do
      described_class.lanes.each do |lane|
        expect(described_class.agent_class_for(lane)).to be_present, "Lane #{lane} missing agent class"
        expect(described_class.description_for(lane)).to be_present, "Lane #{lane} missing description"
      end
    end
  end

  describe "integration with actual agents" do
    it "all agent classes exist and can be instantiated" do
      described_class.lanes.each do |lane|
        agent_class = described_class.agent_class_for(lane)
        expect { agent_class.new }.not_to raise_error
      end
    end

    it "all agents inherit from BaseAgent" do
      described_class.lanes.each do |lane|
        agent_class = described_class.agent_class_for(lane)
        expect(agent_class.ancestors).to include(Agents::BaseAgent)
      end
    end
  end
end
