module State
  class Validator
    class Invalid < StandardError; end

    def call!(state)
      unless state.is_a?(Hash)
        raise Invalid, "state must be a Hash"
      end

      missing = Contract::REQUIRED_KEYS - state.keys
      raise Invalid, "missing keys: #{missing.join(", ")}" if missing.any?

      meta = state["meta"]
      raise Invalid, "meta must be a Hash" unless meta.is_a?(Hash)
      %w[tenant_id wa_id locale timezone current_lane].each do |k|
        raise Invalid, "meta.#{k} missing" if meta[k].nil? && k != "sticky_until"
      end

      # sanity checks
      lane = meta["current_lane"]
      raise Invalid, "invalid lane #{lane}" unless %w[info product commerce support].include?(lane)

      true
    end
  end
end
