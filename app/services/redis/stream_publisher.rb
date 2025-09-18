# frozen_string_literal: true

module Redis
  class StreamPublisher
    include ActiveSupport::Benchmarkable

    class PublishError < StandardError; end

    def initialize(stream_name: nil, consumer_group: nil)
      @stream_name = stream_name || Rails.application.config.redis_stream_name
      @consumer_group = consumer_group || Rails.application.config.redis_consumer_group
    end

    def publish(event_data, idempotency_key: nil)
      benchmark "Redis stream publish", level: :info do
        REDIS_POOL.with do |redis|
          # Check for idempotency if key provided
          if idempotency_key && duplicate_event?(redis, idempotency_key)
            Rails.logger.info({
              at: "redis.stream.duplicate_skipped",
              stream: @stream_name,
              idempotency_key: idempotency_key
            }.to_json)
            return :duplicate_skipped
          end

          # Prepare event payload with metadata
          payload = prepare_payload(event_data, idempotency_key)

          # Publish to Redis stream
          message_id = redis.xadd(@stream_name, payload)

          # Ensure consumer group exists
          ensure_consumer_group(redis)

          Rails.logger.info({
            at: "redis.stream.published",
            stream: @stream_name,
            message_id: message_id,
            idempotency_key: idempotency_key
          }.to_json)

          message_id
        end
      end
    rescue ::Redis::BaseError => e
      Rails.logger.error({
        at: "redis.stream.publish_error",
        error: e.class.name,
        message: e.message,
        stream: @stream_name,
        idempotency_key: idempotency_key
      }.to_json)
      raise PublishError, "Failed to publish to Redis stream: #{e.message}"
    end

    private

    def duplicate_event?(redis, idempotency_key)
      # Check recent messages for duplicate idempotency_key
      # Only check last 1000 messages to avoid performance issues
      recent_messages = redis.xrevrange(@stream_name, "+", "-", count: 1000)

      recent_messages.any? do |_message_id, fields|
        fields_hash = Hash[*fields]
        fields_hash["idempotency_key"] == idempotency_key
      end
    rescue ::Redis::BaseError
      # If we can't check for duplicates, log warning and proceed
      Rails.logger.warn({
        at: "redis.stream.duplicate_check_failed",
        idempotency_key: idempotency_key
      }.to_json)
      false
    end

    def prepare_payload(event_data, idempotency_key)
      {
        "event_type" => event_data[:event_type] || "audio_received",
        "payload" => event_data.to_json,
        "idempotency_key" => idempotency_key,
        "timestamp" => Time.current.iso8601,
        "source" => "lexi-ingestion-api"
      }
    end

    def ensure_consumer_group(redis)
      redis.xgroup(:create, @stream_name, @consumer_group, "$", mkstream: true)
    rescue ::Redis::CommandError => e
      # Group already exists or other Redis-specific error
      unless e.message.include?("BUSYGROUP")
        Rails.logger.warn({
          at: "redis.stream.consumer_group_setup_failed",
          error: e.message,
          stream: @stream_name,
          consumer_group: @consumer_group
        }.to_json)
      end
    end

    def logger
      Rails.logger
    end
  end
end