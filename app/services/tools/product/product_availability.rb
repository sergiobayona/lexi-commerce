# frozen_string_literal: true

module Tools
  module Product
    # ProductAvailability tool for checking if a product is in stock and available
    # This tool does not require state access - it queries inventory data
    class ProductAvailability < RubyLLM::Tool
      description "Check if a product is currently available and in stock. Returns availability status, stock level, and estimated restock date if out of stock."

      param :product_id, type: :string, required: true,
            desc: "Product ID to check availability for"

      def initialize
        # Hard-coded inventory data for MVP
        # TODO: Replace with actual inventory management system integration
        @inventory = {
          "prod_001" => {
            available: true,
            in_stock: true,
            stock_level: "high",
            quantity: 50,
            restock_date: nil,
            lead_time_minutes: 20
          },
          "prod_002" => {
            available: true,
            in_stock: true,
            stock_level: "medium",
            quantity: 15,
            restock_date: nil,
            lead_time_minutes: 20
          },
          "prod_003" => {
            available: true,
            in_stock: true,
            stock_level: "high",
            quantity: 100,
            restock_date: nil,
            lead_time_minutes: 5
          },
          "prod_004" => {
            available: true,
            in_stock: true,
            stock_level: "low",
            quantity: 3,
            restock_date: nil,
            lead_time_minutes: 30
          },
          "prod_005" => {
            available: true,
            in_stock: true,
            stock_level: "medium",
            quantity: 20,
            restock_date: nil,
            lead_time_minutes: 20
          }
        }
      end

      def execute(product_id:)
        Rails.logger.info "[ProductAvailability] Checking availability for product: #{product_id}"

        inventory = @inventory[product_id]

        if inventory.nil?
          return {
            found: false,
            error: "Producto '#{product_id}' no encontrado en inventario",
            message: "No se encontró información de inventario para este producto"
          }
        end

        # Build response based on availability
        response = {
          found: true,
          product_id: product_id,
          available: inventory[:available],
          in_stock: inventory[:in_stock],
          stock_status: build_stock_status(inventory),
          can_order: inventory[:available] && inventory[:in_stock]
        }

        # Add estimated prep time if available
        if inventory[:available] && inventory[:in_stock]
          response[:prep_time] = "#{inventory[:lead_time_minutes]} minutos"
          response[:estimated_ready] = calculate_ready_time(inventory[:lead_time_minutes])
        end

        # Add restock information if out of stock
        if !inventory[:in_stock] && inventory[:restock_date]
          response[:restock_date] = inventory[:restock_date]
          response[:message] = "Producto temporalmente agotado. Disponible nuevamente: #{inventory[:restock_date]}"
        elsif !inventory[:available]
          response[:message] = "Producto no disponible en este momento"
        end

        response
      rescue StandardError => e
        Rails.logger.error "[ProductAvailability] Error: #{e.message}"
        { error: "Error checking product availability: #{e.message}" }
      end

      private

      def build_stock_status(inventory)
        return "out_of_stock" unless inventory[:in_stock]

        case inventory[:stock_level]
        when "high"
          "En stock - Disponible"
        when "medium"
          "En stock - Stock limitado"
        when "low"
          "En stock - Últimas unidades (#{inventory[:quantity]} disponibles)"
        else
          "En stock"
        end
      end

      def calculate_ready_time(minutes)
        ready_at = Time.now + (minutes * 60)
        ready_at.strftime("%H:%M")
      end
    end
  end
end
