# frozen_string_literal: true

require_relative "../../lib/agent_config"

# AgentRegistry provides centralized agent lookup and lifecycle management.
# Agents are lazy-loaded and cached for performance.
# Agent definitions are loaded from config/agents.yml via AgentConfig.
#
# Usage:
#   registry = AgentRegistry.new
#   agent = registry.for_lane("commerce")
#   response = agent.handle(turn: turn, state: state, intent: intent)
class AgentRegistry
  def initialize
    @agents = {}
  end

  # Get agent for the specified lane
  # @param lane [String] Lane identifier (e.g., "info", "product", "commerce", "support")
  # @return [Agents::BaseAgent] Agent instance for the lane
  # @raise [ArgumentError] If lane is not recognized
  def for_lane(lane)
    lane = normalize_lane(lane)
    raise ArgumentError, "Unknown lane: #{lane}" unless valid_lane?(lane)

    @agents[lane] ||= instantiate_agent(lane)
  end

  # Check if agent registry has an agent for the lane
  # @param lane [String] Lane identifier
  # @return [Boolean]
  def has_lane?(lane)
    valid_lane?(normalize_lane(lane))
  end

  # Get all available lanes from configuration
  # @return [Array<String>]
  def available_lanes
    AgentConfig.lanes
  end

  private

  def normalize_lane(lane)
    lane.to_s.downcase.strip
  end

  def valid_lane?(lane)
    AgentConfig.valid_lane?(lane)
  end

  def instantiate_agent(lane)
    agent_class = AgentConfig.agent_class_for(lane)
    raise ArgumentError, "No agent configured for lane: #{lane}" unless agent_class

    agent_class.new
  end
end
