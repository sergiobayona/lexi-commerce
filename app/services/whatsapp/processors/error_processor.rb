module Whatsapp
  module Processors
    # Processes WhatsApp API errors from webhooks
    # Handles three types of errors:
    # 1. System/app/account-level errors (value.errors)
    # 2. Incoming message errors (messages[].errors)
    # 3. Outgoing message status errors (statuses[].errors)
    class ErrorProcessor
      def initialize(value:, webhook_event: nil)
        @value = value
        @webhook_event = webhook_event
      end

      def call
        process_system_errors if @value["errors"].present?
      end

      private

      # System, app, and account-level errors
      # Format: entry.changes.value.errors[]
      def process_system_errors
        Array(@value["errors"]).each do |error_data|
          create_error_record(
            error_type: 'system',
            error_data: error_data,
            provider_message_id: nil,
            wa_message_id: nil
          )
        end
      end

      # Incoming message errors (unsupported messages)
      # Format: entry.changes.value.messages[].errors[]
      def process_message_error(message_data, message_record = nil)
        return unless message_data["errors"].present?

        Array(message_data["errors"]).each do |error_data|
          create_error_record(
            error_type: 'message',
            error_data: error_data,
            provider_message_id: message_data["id"],
            wa_message_id: message_record&.id
          )
        end
      end

      # Outgoing message status errors
      # Format: entry.changes.value.statuses[].errors[]
      def process_status_error(status_data)
        return unless status_data["errors"].present?

        Array(status_data["errors"]).each do |error_data|
          wa_message = WaMessage.find_by(provider_message_id: status_data["id"])

          create_error_record(
            error_type: 'status',
            error_data: error_data,
            provider_message_id: status_data["id"],
            wa_message_id: wa_message&.id
          )
        end
      end

      def create_error_record(error_type:, error_data:, provider_message_id:, wa_message_id:)
        error_level = determine_error_level(error_data)

        error = WaError.create!(
          error_type: error_type,
          error_level: error_level,
          error_code: error_data["code"],
          error_title: error_data["title"],
          error_message: error_data["message"] || error_data["error_data"]&.dig("details"),
          error_details: error_data["error_data"]&.to_json,
          provider_message_id: provider_message_id,
          wa_message_id: wa_message_id,
          webhook_event_id: @webhook_event&.id,
          raw_error_data: error_data
        )

        log_error(error, error_data)
        error
      end

      def determine_error_level(error_data)
        # WhatsApp API doesn't explicitly provide error levels
        # We determine based on error codes and patterns
        code = error_data["code"].to_i

        case code
        when 0..99        # Informational
          'info'
        when 100..199     # Warnings
          'warning'
        else              # Errors
          'error'
        end
      end

      def log_error(error, error_data)
        log_data = {
          at: "whatsapp.error.#{error.error_type}",
          error_type: error.error_type,
          error_level: error.error_level,
          error_code: error.error_code,
          error_title: error.error_title,
          error_message: error.error_message,
          provider_message_id: error.provider_message_id,
          wa_message_id: error.wa_message_id
        }

        case error.error_level
        when 'error'
          Rails.logger.error(log_data.to_json)
        when 'warning'
          Rails.logger.warn(log_data.to_json)
        else
          Rails.logger.info(log_data.to_json)
        end
      end

      class << self
        # Class method for processing message errors
        def process_message_error(message_data, message_record = nil, webhook_event = nil)
          new(value: {}, webhook_event: webhook_event).send(:process_message_error, message_data, message_record)
        end

        # Class method for processing status errors
        def process_status_error(status_data, webhook_event = nil)
          new(value: {}, webhook_event: webhook_event).send(:process_status_error, status_data)
        end
      end
    end
  end
end
