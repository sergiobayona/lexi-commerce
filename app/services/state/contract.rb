require_relative "../../../lib/agent_config"

module State
  module Contract
    CURRENT_VERSION = 3

    DEFAULTS = {
      "meta" => {
        "tenant_id"    => nil,
        "wa_id"        => nil,
        "locale"       => "es-CO",
        "timezone"     => "America/Bogota",
        "current_lane" => AgentConfig.default_lane,
        "sticky_until" => nil,
        "customer_id"  => nil,
        "flags"        => { "human_handoff" => false, "vip" => false }
      },
      "dialogue" => {
        "turns" => [],
        "last_user_msg_id" => nil,
        "last_assistant_msg_id" => nil
      },
      "slots" => {
        "location_id"     => nil,
        "fulfillment"     => nil,
        "address"         => nil,
        "phone_verified"  => false,
        "language_locked" => false
      },
      "commerce" => {
        "state" => "browsing",
        "cart"  => { "items" => [], "subtotal_cents" => 0, "currency" => "COP" },
        "last_quote" => nil
      },
      "support" => {
        "active_case_id" => nil,
        "last_order_id"  => nil,
        "return_window_open" => nil
      },
      "last_tool" => nil,
      "locks"     => { "agent" => nil, "until" => nil },
      "version"   => CURRENT_VERSION
    }.freeze

    # Minimal structural expectations (fast!!)
    REQUIRED_KEYS = %w[meta dialogue slots version].freeze

    def self.blank
      Marshal.load(Marshal.dump(DEFAULTS)) # deep dup
    end

    def self.current_version?(state)
      state.is_a?(Hash) && state["version"] == CURRENT_VERSION
    end
  end
end
