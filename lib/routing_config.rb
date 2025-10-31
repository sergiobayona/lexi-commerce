# frozen_string_literal: true

require "liquid"

# RoutingConfig provides access to the unified routing configuration
# Loads configuration from config/routing.yml
#
# Usage:
#   RoutingConfig.intents           # => { "business_hours" => { "agent" => "info", ... }, ... }
#   RoutingConfig.entities          # => { "product" => { "type" => "string", ... }, ... }
#   RoutingConfig.system_prompt     # => "You are a message router..."
#   RoutingConfig.intent_list       # => ["business_hours", "pricing_quote", ...]
#   RoutingConfig.agent_for_intent("business_hours")  # => "info"
class RoutingConfig
  class ConfigurationError < StandardError; end

  class << self
    # Get all intents
    # @return [Hash] Intent configuration hash
    def intents
      config["intents"] || {}
    end

    # Get all entities
    # @return [Hash] Entity configuration hash
    def entities
      config["entities"] || {}
    end

    # Get system prompt (processed with Liquid templates)
    # @return [String] System prompt for LLM
    # @raise [ConfigurationError] if Liquid template is invalid
    def system_prompt
      raw_prompt = config["system_prompt"]

      # Bug #15 Fix: Handle Liquid template parsing errors
      begin
        # Render Liquid template with intents and entities as variables
        template = Liquid::Template.parse(raw_prompt)
        template.render(
          "intents" => intents,
          "entities" => entities,
          "intent_names" => intents.keys,
          "entity_names" => entities.keys
        )
      rescue Liquid::SyntaxError => e
        raise ConfigurationError, "Invalid Liquid template in system_prompt: #{e.message}"
      rescue StandardError => e
        raise ConfigurationError, "Failed to render system_prompt template: #{e.message}"
      end
    end

    # Get list of intent names
    # @return [Array<String>] Intent names
    def intent_list
      intents.keys
    end

    # Get agent for a specific intent
    # @param intent [String] Intent name
    # @return [String, nil] Agent name
    def agent_for_intent(intent)
      intents.dig(intent, "agent")
    end

    # Get description for a specific intent
    # @param intent [String] Intent name
    # @return [String, nil] Intent description
    def description_for(intent)
      intents.dig(intent, "description")
    end

    # Get examples for a specific intent
    # @param intent [String] Intent name
    # @return [Array<String>] Example messages
    def examples_for(intent)
      intents.dig(intent, "examples") || []
    end

    # Reset cached configuration (useful for testing)
    def reset!
      @config = nil
    end

    private

    # Load and parse configuration from YAML file
    # @return [Hash] Full routing configuration
    # @raise [ConfigurationError] if file not found or invalid
    def config
      @config ||= begin
        config_path = Rails.root.join("config/routing.yml")
        raise ConfigurationError, "routing.yml not found at #{config_path}" unless File.exist?(config_path)

        yaml_content = YAML.load_file(config_path)

        raise ConfigurationError, "routing.yml must be a Hash" unless yaml_content.is_a?(Hash)

        yaml_content
      end
    end
  end
end
