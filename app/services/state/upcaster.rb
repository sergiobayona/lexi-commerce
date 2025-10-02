
module State
  class Upcaster
    def call(state)
      v = state["version"].to_i
      while v < Contract::CURRENT_VERSION
        state = send("v#{v}_to_v#{v+1}", state)
        v += 1
        state["version"] = v
      end
      state
    end

    private

    # Example migrations:

    # v1 -> v2 : move cart from slots → commerce.cart
    # def v1_to_v2(s)
    #   if s.dig("slots", "cart")
    #     s["commerce"] ||= {}
    #     s["commerce"]["cart"] = s["slots"].delete("cart")
    #   end
    #   s
    # end

    # # v2 -> v3 : add support section & last_tool shape change
    # def v2_to_v3(s)
    #   s["support"] ||= { "active_case_id" => nil, "last_order_id" => nil, "return_window_open" => nil }
    #   if s["last_tool"].is_a?(String)
    #     s["last_tool"] = { "name" => s["last_tool"], "ok" => true, "at" => Time.now.utc.iso8601 }
    #   end
    #   s
    # end
  end
end
