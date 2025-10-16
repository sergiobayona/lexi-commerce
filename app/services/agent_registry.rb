# frozen_string_literal: true

# AgentRegistry provides centralized agent lookup and lifecycle management.
# Agents are lazy-loaded and cached for performance.
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
  # @param lane [String] Lane identifier: "info", "commerce", "support"
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

  # Get all available lanes
  # @return [Array<String>]
  def available_lanes
    %w[info commerce support]
  end

  private

  def normalize_lane(lane)
    lane.to_s.downcase.strip
  end

  def valid_lane?(lane)
    available_lanes.include?(lane)
  end

  def instantiate_agent(lane)
    case lane
    when "info"
      Agents::InfoAgent.new
    when "commerce"
      Agents::CommerceAgent.new
    when "support"
      Agents::SupportAgent.new
    when "product"
      Agents::ProductAgent.new
    else
      raise ArgumentError, "No agent configured for lane: #{lane}"
    end
  end
end
