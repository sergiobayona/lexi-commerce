require_relative "../../../lib/agent_config"

module State
  class Validator
    class Invalid < StandardError; end

    def call!(state)
      raise Invalid, "state must be Hash" unless state.is_a?(Hash)
      raise Invalid, "tenant_id missing" if state["tenant_id"].nil?
      raise Invalid, "wa_id missing" if state["wa_id"].nil?
      raise Invalid, "current_lane invalid" unless AgentConfig.valid_lane?(state["current_lane"])

      true
    end
  end
end
