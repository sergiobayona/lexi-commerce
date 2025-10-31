# frozen_string_literal: true

module State
  module Accessors
    # CaseAccessor provides controlled access to the support case state slice
    # Encapsulates case operations and prevents direct state manipulation
    #
    # Usage:
    #   accessor = CaseAccessor.new(state)
    #   case_info = accessor.get_active_case
    #   accessor.create_case(type: "refund", details: {...})
    class CaseAccessor
      def initialize(state)
        @state = state
        ensure_support_initialized!
      end

      # Get the active case ID
      # @return [String, nil] Active case ID or nil if none
      def active_case_id
        support_state.dig("active_case_id")
      end

      # Get active case details
      # @return [Hash, nil] Case details or nil if no active case
      def get_active_case
        case_id = active_case_id
        return nil unless case_id

        {
          case_id: case_id,
          case_type: support_state.dig("case_type"),
          opened_at: support_state.dig("opened_at"),
          status: support_state.dig("case_status") || "open",
          escalation_level: support_state.dig("escalation_level") || 0
        }
      end

      # Check if there's an active case
      # @return [Boolean]
      def has_active_case?
        !active_case_id.nil?
      end

      # Get case history (list of all case IDs in this session)
      # @return [Array<String>] Case IDs
      def case_history
        support_state.dig("case_history") || []
      end

      # Create a new support case (returns state patch)
      # @param type [String] Case type (e.g., "refund", "complaint", "technical")
      # @param details [Hash] Case details
      # @return [Hash] State patch to apply
      def create_case(type:, details: {})
        case_id = generate_case_id

        # Add to case history
        history = case_history.dup
        history << case_id

        {
          "support" => {
            "active_case_id" => case_id,
            "case_type" => type,
            "case_status" => "open",
            "case_details" => details,
            "opened_at" => Time.now.utc.iso8601,
            "escalation_level" => 0,
            "case_history" => history,
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Update active case details (returns state patch)
      # @param updates [Hash] Fields to update
      # @return [Hash] State patch to apply
      def update_case(updates: {})
        return { error: "No active case to update" } unless has_active_case?

        state_patch = {
          "support" => {
            "last_update" => Time.now.utc.iso8601
          }
        }

        # Merge allowed updates
        allowed_fields = [ "case_status", "case_details", "escalation_level", "notes" ]
        updates.each do |key, value|
          if allowed_fields.include?(key.to_s)
            state_patch["support"][key.to_s] = value
          end
        end

        state_patch
      end

      # Close active case (returns state patch)
      # @param resolution [String] Resolution summary
      # @return [Hash] State patch to apply
      def close_case(resolution: nil)
        return { error: "No active case to close" } unless has_active_case?

        {
          "support" => {
            "active_case_id" => nil,
            "case_status" => "closed",
            "closed_at" => Time.now.utc.iso8601,
            "resolution" => resolution,
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Escalate case (increases escalation level, returns state patch)
      # @param reason [String] Escalation reason
      # @return [Hash] State patch to apply
      def escalate_case(reason: nil)
        return { error: "No active case to escalate" } unless has_active_case?

        current_level = support_state.dig("escalation_level") || 0
        new_level = current_level + 1

        {
          "support" => {
            "escalation_level" => new_level,
            "escalation_reason" => reason,
            "escalated_at" => Time.now.utc.iso8601,
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Request human handoff (returns state patch)
      # @return [Hash] State patch to apply
      def request_human_handoff
        {
          "meta" => {
            "flags" => {
              "human_handoff" => true
            }
          },
          "support" => {
            "handoff_requested_at" => Time.now.utc.iso8601,
            "last_update" => Time.now.utc.iso8601
          }
        }
      end

      # Check if human handoff was requested
      # @return [Boolean]
      def human_handoff_requested?
        @state.dig("meta", "flags", "human_handoff") == true
      end

      # Get case summary for display
      # @return [Hash] Formatted case data
      def summary
        active_case = get_active_case

        if active_case
          {
            has_active_case: true,
            case_id: active_case[:case_id],
            case_type: active_case[:case_type],
            status: active_case[:status],
            opened_at: active_case[:opened_at],
            escalation_level: active_case[:escalation_level],
            human_handoff_requested: human_handoff_requested?,
            case_count: case_history.size
          }
        else
          {
            has_active_case: false,
            case_count: case_history.size,
            human_handoff_requested: human_handoff_requested?
          }
        end
      end

      private

      def support_state
        @state.dig("support") || {}
      end

      def ensure_support_initialized!
        @state["support"] ||= {}
      end

      def generate_case_id
        "case_#{SecureRandom.hex(4)}"
      end
    end
  end
end
