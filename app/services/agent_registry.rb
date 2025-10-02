class AgentRegistry
  def initialize(info:, commerce:, support:)
    @agents = { "info" => info, "commerce" => commerce, "support" => support }
  end

  def for_lane(lane)
    @agents.fetch(lane.to_s) # raises if misconfigured
  end
end
