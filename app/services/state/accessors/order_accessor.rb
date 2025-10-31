# frozen_string_literal: true

module State
  module Accessors
    # OrderAccessor provides controlled access to the order state slice
    # Encapsulates order verification and tracking operations
    #
    # Usage:
    #   accessor = OrderAccessor.new(state)
    #   verified = accessor.verified?
    #   accessor.set_verified(order_id, phone)
    class OrderAccessor
      def initialize(state)
        @state = state
        ensure_order_initialized!
      end

      # Check if customer is verified for order access
      # @return [Boolean]
      def verified?
        order_state.dig("verified") == true
      end

      # Get last looked up order ID
      # @return [String, nil]
      def last_order_id
        order_state.dig("last_lookup")
      end

      # Get verification timestamp
      # @return [String, nil] ISO8601 timestamp
      def verified_at
        order_state.dig("verified_at")
      end

      # Set verification status (returns state patch)
      # @param order_id [String] Order ID that was verified
      # @param phone [String] Phone number used for verification
      # @return [Hash] State patch to apply
      def set_verified(order_id:, phone:)
        {
          "order" => {
            "verified" => true,
            "verified_at" => Time.now.utc.iso8601,
            "verified_order_id" => order_id,
            "verified_phone" => phone
          }
        }
      end

      # Clear verification status (returns state patch)
      # @return [Hash] State patch to apply
      def clear_verification
        {
          "order" => {
            "verified" => false,
            "verified_at" => nil,
            "verified_order_id" => nil,
            "verified_phone" => nil
          }
        }
      end

      # Record order lookup (returns state patch)
      # @param order_id [String] Order ID that was looked up
      # @param result [Hash] Lookup result data
      # @return [Hash] State patch to apply
      def record_lookup(order_id:, result: {})
        {
          "order" => {
            "last_lookup" => order_id,
            "last_lookup_at" => Time.now.utc.iso8601,
            "last_lookup_result" => result
          }
        }
      end

      # Get order lookup history
      # @return [Array<String>] Order IDs that have been looked up
      def lookup_history
        order_state.dig("lookup_history") || []
      end

      # Add to lookup history (returns state patch)
      # @param order_id [String] Order ID to add to history
      # @return [Hash] State patch to apply
      def add_to_history(order_id:)
        history = lookup_history.dup
        history << order_id unless history.include?(order_id)

        {
          "order" => {
            "lookup_history" => history
          }
        }
      end

      # Check if customer can access order info without verification
      # (e.g., if phone is verified and customer_id matches)
      # @return [Boolean]
      def can_access_without_verification?
        @state["phone_verified"] == true && @state["customer_id"].present?
      end

      # Get summary of order state
      # @return [Hash] Order state summary
      def summary
        {
          verified: verified?,
          verified_at: verified_at,
          last_order_id: last_order_id,
          lookup_count: lookup_history.size,
          can_access: verified? || can_access_without_verification?,
          customer_verified: @state["phone_verified"] == true
        }
      end

      private

      def order_state
        @state.dig("order") || {}
      end

      def ensure_order_initialized!
        @state["order"] ||= {}
      end
    end
  end
end
