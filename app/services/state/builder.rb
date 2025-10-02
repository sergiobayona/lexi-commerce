require "time"

module State
  class Builder
    def initialize(contract: Contract)
      @contract = contract
    end

    # Create a fresh state with contextual seed data
    def new_session(tenant_id:, wa_id:, locale: "es-CO", timezone: "America/Bogota")
      s = @contract.blank
      s["meta"]["tenant_id"] = tenant_id
      s["meta"]["wa_id"]     = wa_id
      s["meta"]["locale"]    = locale
      s["meta"]["timezone"]  = timezone
      s
    end

    # Hydrate from persisted JSON (e.g. Redis string), upcast if needed, fill missing defaults
    def from_json(json_str)
      raw = (json_str && json_str.size > 1) ? JSON.parse(json_str) : {}
      state = deep_merge(@contract.blank, raw)       # fill defaults
      state = Upcaster.new.call(state) unless Contract.current_version?(state)
      state
    end

    private

    def deep_merge(a, b)
      a.merge(b) do |_, av, bv|
        if av.is_a?(Hash) && bv.is_a?(Hash)
          deep_merge(av, bv)
        else
          bv
        end
      end
    end
  end
end
