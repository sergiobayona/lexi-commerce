require_relative "../../../lib/agent_config"

module State
  module Contract
    DEFAULTS = {
      # Session identity
      "tenant_id"    => nil,
      "wa_id"        => nil,
      "locale"       => "es-CO",
      "timezone"     => "America/Bogota",

      # Routing
      "current_lane" => AgentConfig.default_lane,

      # Customer
      "customer_id"     => nil,
      "human_handoff"   => false,
      "vip"             => false,

      # Dialogue
      "turns"                  => [],
      "last_user_msg_id"       => nil,
      "last_assistant_msg_id"  => nil,

      # Slots
      "location_id"     => nil,
      "fulfillment"     => nil,
      "address"         => nil,
      "phone_verified"  => false,
      "language_locked" => false,

      # Commerce
      "commerce_state"      => "browsing",
      "cart_items"          => [],
      "cart_subtotal_cents" => 0,
      "cart_currency"       => "COP",
      "last_quote"          => nil,

      # Support
      "active_case_id"      => nil,
      "last_order_id"       => nil,
      "return_window_open"  => nil,

      # Misc
      "last_tool"    => nil,
      "locked_agent" => nil,
      "locked_until" => nil,

      # Metadata
      "updated_at" => nil
    }.freeze

    # Minimal structural expectations (fast!!)
    REQUIRED_KEYS = %w[tenant_id wa_id current_lane].freeze

    def self.blank
      Marshal.load(Marshal.dump(DEFAULTS)) # deep dup
    end
  end
end
