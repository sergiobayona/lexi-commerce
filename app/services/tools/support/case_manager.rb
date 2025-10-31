# frozen_string_literal: true

module Tools
  module Support
    # CaseManager tool for creating and managing support cases
    # Requires state access via CaseAccessor for case operations
    class CaseManager < RubyLLM::Tool
      description "Manage support cases: create, update, close, escalate, or view case details. Handles refund requests, complaints, technical issues, and more."

      param :action, type: :string, required: true,
            desc: "Action: 'create', 'update', 'close', 'escalate', 'view', 'request_human'"
      param :case_type, type: :string, required: false,
            desc: "Type for create action: 'refund', 'complaint', 'technical', 'cancellation', 'general'"
      param :details, type: :string, required: false,
            desc: "Case details or update information"
      param :reason, type: :string, required: false,
            desc: "Reason for escalation or closure"

      def initialize(case_accessor_provider)
        @case_accessor_provider = case_accessor_provider
      end

      def execute(action:, case_type: nil, details: nil, reason: nil)
        Rails.logger.info "[CaseManager] Action: #{action}, Type: #{case_type}, Details: #{details}"

        # Get case accessor (provided by agent with current state)
        cases = @case_accessor_provider.call

        case action.downcase
        when "create"
          create_case(cases, case_type, details)
        when "update"
          update_case(cases, details)
        when "close"
          close_case(cases, reason)
        when "escalate"
          escalate_case(cases, reason)
        when "view"
          view_case(cases)
        when "request_human"
          request_human_handoff(cases)
        else
          { error: "Invalid action '#{action}'. Valid actions: create, update, close, escalate, view, request_human" }
        end
      rescue StandardError => e
        Rails.logger.error "[CaseManager] Error: #{e.message}"
        { error: "Case management failed: #{e.message}" }
      end

      private

      def create_case(cases, case_type, details)
        return { error: "case_type is required for create action" } unless case_type

        # Check if there's already an active case
        if cases.has_active_case?
          existing_case = cases.get_active_case
          return {
            error: "Ya existe un caso activo: #{existing_case[:case_id]}",
            existing_case: existing_case,
            message: "Por favor cierra el caso actual antes de crear uno nuevo, o continúa con el caso existente"
          }
        end

        # Parse details if provided
        case_details = details ? { description: details } : {}

        # Create case and get state patch
        state_patch = cases.create_case(
          type: case_type,
          details: case_details
        )

        {
          action: "create",
          success: true,
          case: {
            case_id: state_patch.dig("support", "active_case_id"),
            case_type: case_type,
            status: "open",
            created_at: state_patch.dig("support", "opened_at")
          },
          message: "✅ Caso #{state_patch.dig('support', 'active_case_id')} creado exitosamente",
          state_patch: state_patch
        }
      end

      def update_case(cases, details)
        unless cases.has_active_case?
          return { error: "No hay caso activo para actualizar" }
        end

        updates = details ? { notes: details } : {}
        state_patch = cases.update_case(updates: updates)

        if state_patch[:error]
          return state_patch
        end

        active_case = cases.get_active_case

        {
          action: "update",
          success: true,
          case: active_case,
          message: "✏️ Caso actualizado",
          state_patch: state_patch
        }
      end

      def close_case(cases, reason)
        unless cases.has_active_case?
          return { error: "No hay caso activo para cerrar" }
        end

        active_case = cases.get_active_case
        state_patch = cases.close_case(resolution: reason)

        {
          action: "close",
          success: true,
          case_id: active_case[:case_id],
          resolution: reason,
          message: "✅ Caso #{active_case[:case_id]} cerrado exitosamente",
          state_patch: state_patch
        }
      end

      def escalate_case(cases, reason)
        unless cases.has_active_case?
          return { error: "No hay caso activo para escalar" }
        end

        active_case = cases.get_active_case
        state_patch = cases.escalate_case(reason: reason)

        new_level = state_patch.dig("support", "escalation_level")

        {
          action: "escalate",
          success: true,
          case_id: active_case[:case_id],
          new_escalation_level: new_level,
          reason: reason,
          message: "⬆️ Caso escalado al nivel #{new_level}",
          state_patch: state_patch
        }
      end

      def view_case(cases)
        summary = cases.summary

        if summary[:has_active_case]
          active_case = cases.get_active_case
          {
            action: "view",
            case: active_case,
            summary: summary,
            message: "📋 Caso activo: #{active_case[:case_id]} (#{active_case[:case_type]})"
          }
        else
          {
            action: "view",
            summary: summary,
            message: "No hay casos activos. Total de casos: #{summary[:case_count]}"
          }
        end
      end

      def request_human_handoff(cases)
        # Can request handoff even without active case
        state_patch = cases.request_human_handoff

        {
          action: "request_human",
          success: true,
          message: "👤 Solicitando conexión con agente humano. Tiempo de espera estimado: 5-10 minutos",
          state_patch: state_patch
        }
      end
    end
  end
end
