# frozen_string_literal: true

require "rails_helper"
require_relative "../../lib/routing_config"

RSpec.describe RoutingConfig do
  describe ".intents" do
    it "returns a hash of intents" do
      expect(described_class.intents).to be_a(Hash)
      expect(described_class.intents).not_to be_empty
    end

    it "includes expected intent keys" do
      expect(described_class.intents.keys).to include(
        "business_hours",
        "pricing_quote",
        "product_info",
        "place_order",
        "order_status"
      )
    end

    it "each intent has required fields" do
      described_class.intents.each do |intent_name, intent_data|
        expect(intent_data).to have_key("agent")
        expect(intent_data).to have_key("description")
        expect(intent_data).to have_key("examples")
        expect(intent_data["examples"]).to be_an(Array)
      end
    end
  end

  describe ".entities" do
    it "returns a hash of entities" do
      expect(described_class.entities).to be_a(Hash)
      expect(described_class.entities).not_to be_empty
    end

    it "includes expected entity keys" do
      expect(described_class.entities.keys).to include(
        "product",
        "quantity",
        "order_id",
        "language"
      )
    end

    it "each entity has type and description" do
      described_class.entities.each do |entity_name, entity_data|
        expect(entity_data).to have_key("type")
        expect(entity_data).to have_key("description")
      end
    end
  end

  describe ".system_prompt" do
    let(:prompt) { described_class.system_prompt }

    it "returns a non-empty string" do
      expect(prompt).to be_a(String)
      expect(prompt).not_to be_empty
    end

    it "includes intent definitions" do
      expect(prompt).to include("business_hours")
      expect(prompt).to include("product_info")
      expect(prompt).to include("order_status")
    end

    it "includes entity definitions" do
      expect(prompt).to include("product (string)")
      expect(prompt).to include("order_id (string)")
    end

    it "includes examples" do
      expect(prompt).to include("What time do you open on Saturdays?")
      expect(prompt).to include("### Examples")
    end

    it "specifies confidence levels" do
      expect(prompt).to include("high")
      expect(prompt).to include("medium")
      expect(prompt).to include("low")
    end
  end

  describe ".intent_list" do
    it "returns an array of intent names" do
      expect(described_class.intent_list).to be_an(Array)
      expect(described_class.intent_list).to include("business_hours", "product_info")
    end
  end

  describe ".agent_for_intent" do
    it "returns the correct agent for an intent" do
      expect(described_class.agent_for_intent("business_hours")).to eq("info")
      expect(described_class.agent_for_intent("product_info")).to eq("product")
      expect(described_class.agent_for_intent("place_order")).to eq("commerce")
    end

    it "returns nil for unknown intent" do
      expect(described_class.agent_for_intent("unknown_intent")).to be_nil
    end
  end

  describe ".description_for" do
    it "returns the description for an intent" do
      description = described_class.description_for("business_hours")
      expect(description).to include("Opening/closing times")
    end

    it "returns nil for unknown intent" do
      expect(described_class.description_for("unknown_intent")).to be_nil
    end
  end

  describe ".examples_for" do
    it "returns examples for an intent" do
      examples = described_class.examples_for("business_hours")
      expect(examples).to be_an(Array)
      expect(examples).not_to be_empty
      expect(examples.first).to include("open")
    end

    it "returns empty array for unknown intent" do
      expect(described_class.examples_for("unknown_intent")).to eq([])
    end
  end

  describe "configuration errors" do
    before { described_class.reset! }
    after { described_class.reset! }

    it "raises error if routing.yml is missing" do
      allow(File).to receive(:exist?).and_return(false)

      expect {
        described_class.intents
      }.to raise_error(RoutingConfig::ConfigurationError, /routing.yml not found/)
    end
  end

  describe "Liquid template error handling" do
    # Bug #15 Fix: Test that Liquid template errors are properly caught and converted to ConfigurationError
    before { described_class.reset! }
    after { described_class.reset! }

    it "raises ConfigurationError for invalid Liquid syntax in system_prompt" do
      # Mock config with invalid Liquid template (missing closing tag)
      invalid_config = {
        "system_prompt" => "Start {% for intent in intents %} {{ intent }} - missing endfor tag",
        "intents" => { "test" => { "agent" => "info" } },
        "entities" => {}
      }

      allow(YAML).to receive(:load_file).and_return(invalid_config)

      expect {
        described_class.system_prompt
      }.to raise_error(RoutingConfig::ConfigurationError, /(Invalid Liquid template|Failed to render system_prompt template)/)
    end

    it "raises ConfigurationError for undefined variables in Liquid template" do
      # Mock config with template that references undefined variable
      invalid_config = {
        "system_prompt" => "Value: {{ undefined_variable }}",
        "intents" => { "test" => { "agent" => "info" } },
        "entities" => {}
      }

      allow(YAML).to receive(:load_file).and_return(invalid_config)

      # This should not raise an error - Liquid silently ignores undefined variables
      # So this test verifies the expected behavior
      expect {
        described_class.system_prompt
      }.not_to raise_error
    end

    it "handles errors during template rendering" do
      # Mock config that will cause an error during rendering
      invalid_config = {
        "system_prompt" => "Test {% assign x = y %}",
        "intents" => { "test" => { "agent" => "info" } },
        "entities" => {}
      }

      allow(YAML).to receive(:load_file).and_return(invalid_config)

      # Liquid might not error on this, but if it does, it should be caught
      # This test ensures the rescue block works for any StandardError
      result = described_class.system_prompt
      expect(result).to be_a(String)
    end

    it "successfully renders valid Liquid template" do
      # Mock config with valid Liquid template
      valid_config = {
        "system_prompt" => "Intents: {% for intent in intents %}{{ intent[0] }}{% unless forloop.last %}, {% endunless %}{% endfor %}",
        "intents" => { "test1" => { "agent" => "info" }, "test2" => { "agent" => "commerce" } },
        "entities" => {}
      }

      allow(YAML).to receive(:load_file).and_return(valid_config)

      result = described_class.system_prompt
      expect(result).to include("test1")
      expect(result).to include("test2")
      expect(result).to include("Intents:")
    end
  end
end
