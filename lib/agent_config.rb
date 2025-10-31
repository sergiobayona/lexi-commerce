# frozen_string_literal: true

# AgentConfig provides a single source of truth for agent/lane definitions
# Loads configuration from config/routing.yml
#
# Usage:
#   AgentConfig.lanes                    # => ["info", "product", "commerce", "support"]
#   AgentConfig.default_lane             # => "info"
#   AgentConfig.valid_lane?("commerce")  # => true
#   AgentConfig.agent_class_for("info")  # => Agents::InfoAgent
#   AgentConfig.description_for("info")  # => "General business information..."
#
# Adding a new agent:
#   1. Add entry to config/routing.yml under 'agents' section
#   2. Create agent class (e.g., app/services/agents/billing_agent.rb)
#   3. Done! All validations and routing automatically include new agent
class AgentConfig
  class ConfigurationError < StandardError; end

  class << self
    # Get all available lane names
    # @return [Array<String>] Sorted array of lane names
    def lanes
      @lanes ||= config.keys.sort
    end

    # Get the default lane (marked with is_default: true in YAML)
    # Falls back to first lane if no default specified
    # @return [String] Default lane name
    def default_lane
      @default_lane ||= begin
        default = config.find { |_, v| v["is_default"] }&.first
        default || lanes.first || raise(ConfigurationError, "No agents configured")
      end
    end

    # Get agent class for a specific lane
    # @param lane [String] Lane identifier
    # @return [Class, nil] Agent class or nil if not found
    def agent_class_for(lane)
      class_name = config.dig(lane.to_s, "class_name")
      return nil unless class_name

      class_name.constantize
    rescue NameError => e
      raise ConfigurationError, "Agent class '#{class_name}' not found for lane '#{lane}': #{e.message}"
    end

    # Get description for a specific lane
    # @param lane [String] Lane identifier
    # @return [String, nil] Lane description or nil if not found
    def description_for(lane)
      config.dig(lane.to_s, "description")
    end

    # Get model for a specific lane
    # @param lane [String] Lane identifier
    # @return [String] Model name (defaults to "gpt-4o-mini" if not specified)
    def model_for(lane)
      config.dig(lane.to_s, "model") || "gpt-4o-mini"
    end

    # Get hash of all lane descriptions
    # @return [Hash<String, String>] Map of lane names to descriptions
    def lane_descriptions
      @lane_descriptions ||= config.transform_values { |v| v["description"] }
    end

    # Check if a lane is valid
    # @param lane [String, Symbol] Lane identifier
    # @return [Boolean] true if lane exists in configuration
    def valid_lane?(lane)
      lanes.include?(lane.to_s)
    end

    # Reset cached configuration (useful for testing)
    # @return [void]
    def reset!
      @config = nil
      @lanes = nil
      @default_lane = nil
      @lane_descriptions = nil
    end

    private

    # Load and parse configuration from YAML file
    # @return [Hash] Agent configuration hash
    # @raise [ConfigurationError] if file not found or invalid
    def config
      @config ||= begin
        config_path = Rails.root.join("config/routing.yml")
        raise ConfigurationError, "routing.yml not found at #{config_path}" unless File.exist?(config_path)

        yaml_content = YAML.load_file(config_path)
        agents = yaml_content["agents"]

        raise ConfigurationError, "routing.yml must contain 'agents' key" unless agents.is_a?(Hash)
        raise ConfigurationError, "routing.yml 'agents' section is empty" if agents.empty?

        validate_config!(agents)
        agents
      end
    end

    # Validate configuration structure and constraints
    # @param agents [Hash] Agent configuration to validate
    # @return [void]
    # @raise [ConfigurationError] if configuration is invalid
    def validate_config!(agents)
      # Validate each agent entry
      agents.each do |lane, definition|
        unless definition.is_a?(Hash)
          raise ConfigurationError, "Agent '#{lane}' must be a hash, got #{definition.class}"
        end

        unless definition["class_name"]
          raise ConfigurationError, "Agent '#{lane}' missing required 'class_name' field"
        end

        unless definition["description"]
          raise ConfigurationError, "Agent '#{lane}' missing required 'description' field"
        end
      end

      # Validate only one default lane
      defaults = agents.select { |_, v| v["is_default"] }
      if defaults.size > 1
        raise ConfigurationError, "Only one agent can be marked as default, found: #{defaults.keys.join(", ")}"
      end
    end
  end
end
