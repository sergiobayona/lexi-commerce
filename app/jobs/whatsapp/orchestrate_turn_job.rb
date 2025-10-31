# frozen_string_literal: true

module Whatsapp
  # OrchestrateTurnJob coordinates the conversation flow for a single WhatsApp message.
  # It converts the message to a turn, processes it through the State::Controller,
  # manages session state, routes to appropriate agents, and prepares responses.
  #
  # Current Phase: Orchestration and logging (no actual message sending yet)
  # Next Phase: Will trigger SendResponseJob to send agent responses via WhatsApp API
  #
  # Usage:
  #   Whatsapp::OrchestrateTurnJob.perform_later(wa_message)
  class OrchestrateTurnJob < ApplicationJob
    queue_as :high_priority

    # Maximum number of retries for transient failures (only in production with Solid Queue)
    # Polynomial backoff: 4s, 16s, 36s (attempt^2 seconds)
    # Note: Inline adapter (development) doesn't support delayed retries
    retry_on StandardError, wait: :polynomially_longer, attempts: 3 unless Rails.env.development?

    def perform(wa_message)
      # Skip if message is nil, outbound, or already processed
      return if wa_message.nil?
      return if wa_message.direction_outbound?
      return if already_orchestrated?(wa_message)

      # Build turn from message
      turn = build_turn(wa_message)

      # Initialize State::Controller with dependencies
      controller = build_controller

      # Process turn through orchestration
      result = controller.handle_turn(turn)

      # Log orchestration result
      log_orchestration_result(wa_message, result)

      if result.success && result.messages.present?
        enqueue_response_job(wa_message, result.messages)
      end

      # Mark as orchestrated to prevent duplicate processing
      mark_orchestrated(wa_message)

    rescue => e
      Rails.logger.error({
        at: "orchestrate_turn.error",
        wa_message_id: wa_message&.id,
        provider_message_id: wa_message&.provider_message_id,
        error_class: e.class.name,
        error_message: e.message,
        backtrace: e.backtrace.first(5)
      }.to_json)
      raise # Re-raise for job retry mechanism
    end

    private

    def build_turn(wa_message)
      Whatsapp::TurnBuilder.new(wa_message).build
    end

    def build_controller
      State::Controller.new(
        redis: redis_connection,
        router: intent_router,
        registry: agent_registry,
        builder: state_builder,
        validator: state_validator,
        logger: Rails.logger
      )
    end

    def redis_connection
      @redis_connection ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end

    def intent_router
      @intent_router ||= IntentRouter.new
    end

    def agent_registry
      @agent_registry ||= AgentRegistry.new
    end

    def state_builder
      @state_builder ||= State::Builder.new
    end

    def state_validator
      @state_validator ||= State::Validator.new
    end

    def already_orchestrated?(wa_message)
      # Check if we've already processed this message
      # Using Redis to track orchestrated messages with 1-hour TTL
      redis_connection.exists?("orchestrated:#{wa_message.provider_message_id}")
    end

    def mark_orchestrated(wa_message)
      # Mark message as orchestrated to prevent duplicate processing
      redis_connection.setex(
        "orchestrated:#{wa_message.provider_message_id}",
        3600, # 1 hour TTL
        "1"
      )
    end

    def log_orchestration_result(wa_message, result)
      log_data = {
        at: "orchestrate_turn.completed",
        wa_message_id: wa_message.id,
        provider_message_id: wa_message.provider_message_id,
        wa_id: wa_message.wa_contact.wa_id,
        success: result.success,
        lane: result.lane,
        state_version: result.state_version,
        messages_count: result.messages&.size || 0
      }

      if result.error
        log_data[:error] = result.error
        Rails.logger.warn(log_data.to_json)
      else
        Rails.logger.info(log_data.to_json)
      end
    end

    def enqueue_response_job(wa_message, messages)
      # Serialize messages to ensure they're JSON-compatible for ActiveJob
      # RubyLLM::Message objects cannot be serialized by ActiveJob
      serializable_messages = serialize_messages(messages)

      Whatsapp::SendResponseJob.perform_later(
        wa_message: wa_message,
        messages: serializable_messages
      )
    end

    # Convert messages to JSON-serializable format
    # Handles RubyLLM::Message objects and plain hashes with recursive deep serialization
    def serialize_messages(messages)
      return [] if messages.nil?

      Array(messages).map do |message|
        serialize_message_value(message)
      end
    end

    # Recursively serialize a message value (handles nested structures)
    def serialize_message_value(value)
      # Check for RubyLLM::Message first (before Hash, since it might also respond to hash methods)
      if defined?(RubyLLM::Message) && value.is_a?(RubyLLM::Message)
        # Extract text content from RubyLLM::Message objects
        value.content.to_s
      elsif value.is_a?(Hash)
        # Recursively serialize hash values to handle nested RubyLLM::Message objects
        value.each_with_object({}) do |(key, val), result|
          result[key.to_s] = serialize_message_value(val)
        end
      elsif value.is_a?(Array)
        # Recursively serialize array elements
        value.map { |item| serialize_message_value(item) }
      else
        # Return primitive values as-is (String, Integer, Boolean, nil, etc.)
        value
      end
    end
  end
end
