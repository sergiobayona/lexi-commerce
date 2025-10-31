# frozen_string_literal: true

module Tools
  module Support
    # RefundPolicy tool for getting refund, return, and exchange policy information
    # This tool does not require state access - it provides static policy information
    class RefundPolicy < RubyLLM::Tool
      description "Get information about refund, return, and exchange policies. Provides detailed policy information for different scenarios."

      param :policy_type, type: :string, required: true,
            desc: "Type of policy: 'refund', 'return', 'exchange', 'cancellation', 'general'"
      param :scenario, type: :string, required: false,
            desc: "Specific scenario (e.g., 'defective_product', 'wrong_item', 'change_of_mind')"

      def initialize
        # Hard-coded policies for MVP
        # TODO: Load from configuration or database
        @policies = {
          "refund" => {
            title: "Política de Reembolsos",
            summary: "Reembolsos completos dentro de 7 días para pedidos sin abrir",
            conditions: [
              "Producto sin abrir o sin usar",
              "Dentro de 7 días de la compra",
              "Comprobante de compra requerido",
              "El producto debe estar en su empaque original"
            ],
            timeframe: "7 días desde la compra",
            method: "Reembolso al método de pago original en 5-10 días hábiles",
            exceptions: [
              "Productos perecederos (comida) no son reembolsables",
              "Artículos en oferta/descuento pueden tener restricciones"
            ]
          },
          "return" => {
            title: "Política de Devoluciones",
            summary: "Devoluciones aceptadas dentro de 14 días",
            conditions: [
              "Producto en condiciones originales",
              "Empaque intacto",
              "Comprobante de compra",
              "Artículo no utilizado"
            ],
            timeframe: "14 días desde la entrega",
            method: "Recogeremos el producto o lo puedes devolver en tienda",
            exceptions: [
              "Productos alimenticios no son devolvibles por razones de salud",
              "Artículos personalizados no son devolvibles"
            ]
          },
          "exchange" => {
            title: "Política de Cambios",
            summary: "Cambios por talla, color o producto similar disponibles",
            conditions: [
              "Dentro de 14 días de la compra",
              "Producto sin usar en empaque original",
              "Cambio por producto de igual o mayor valor"
            ],
            timeframe: "14 días desde la compra",
            method: "Cambio inmediato en tienda o enviamos reemplazo",
            exceptions: [
              "Sujeto a disponibilidad de inventario",
              "Productos en oferta pueden no ser elegibles"
            ]
          },
          "cancellation" => {
            title: "Política de Cancelaciones",
            summary: "Cancelaciones gratuitas antes de que el pedido sea preparado",
            conditions: [
              "Pedido aún no ha sido preparado/enviado",
              "Contactar dentro de 30 minutos del pedido",
              "Cancelación por WhatsApp o teléfono"
            ],
            timeframe: "Antes de que el pedido entre en preparación",
            method: "Reembolso completo automático en 24-48 horas",
            exceptions: [
              "Una vez el pedido está en preparación, no se puede cancelar",
              "Pedidos ya enviados no son cancelables"
            ]
          },
          "general" => {
            title: "Políticas Generales de Satisfacción",
            summary: "Tu satisfacción es nuestra prioridad",
            key_points: [
              "🔄 Devoluciones: 14 días",
              "💰 Reembolsos: 7 días",
              "🔁 Cambios: 14 días",
              "❌ Cancelaciones: Antes de preparación",
              "📞 Soporte: Disponible para cualquier problema"
            ],
            contact_info: {
              phone: "(555) 123-4567",
              email: "soporte@tonyspizza.com",
              hours: "Lunes a Domingo, 9 AM - 10 PM"
            }
          }
        }
      end

      def execute(policy_type:, scenario: nil)
        Rails.logger.info "[RefundPolicy] Type: #{policy_type}, Scenario: #{scenario}"

        policy_key = policy_type.downcase
        policy = @policies[policy_key]

        if policy.nil?
          return {
            found: false,
            error: "Policy type '#{policy_type}' not found",
            available_types: @policies.keys,
            message: "Tipos de políticas disponibles: #{@policies.keys.join(', ')}"
          }
        end

        # Build response based on scenario if provided
        response = {
          found: true,
          policy_type: policy_type,
          policy: policy
        }

        # Add scenario-specific guidance if provided
        if scenario
          response[:scenario_guidance] = get_scenario_guidance(policy_key, scenario)
        end

        response
      rescue StandardError => e
        Rails.logger.error "[RefundPolicy] Error: #{e.message}"
        { error: "Error fetching policy: #{e.message}" }
      end

      private

      def get_scenario_guidance(policy_type, scenario)
        scenario_guides = {
          "refund" => {
            "defective_product" => "Producto defectuoso: Reembolso completo + reemplazo gratuito si está disponible",
            "wrong_item" => "Artículo incorrecto: Reembolso completo inmediato + envío correcto sin costo",
            "change_of_mind" => "Cambio de opinión: Reembolso completo si el producto está sin abrir (dentro de 7 días)"
          },
          "return" => {
            "defective_product" => "Devolución con recolección gratuita + reembolso completo",
            "wrong_item" => "Devolución inmediata + envío del producto correcto sin costo",
            "not_satisfied" => "Devolución aceptada dentro de 14 días si el producto está en condiciones originales"
          }
        }

        guides = scenario_guides[policy_type] || {}
        guides[scenario] || "Contacta a soporte para asistencia específica con tu situación"
      end
    end
  end
end
