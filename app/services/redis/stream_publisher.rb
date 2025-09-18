# frozen_string_literal: true

module Redis
  class StreamPublisher
    class PublishError < StandardError; end

    def initialize(stream_name: nil, consumer_group: nil)
      @stream_name = stream_name || Rails.application.config.redis_stream_name
      @consumer_group = consumer_group || Rails.application.config.redis_consumer_group
    end

    def publish(event_data, idempotency_key: nil)
      REDIS_POOL.with do |redis|
        # Simple duplicate check using idempotency key
        if idempotency_key && duplicate_event?(redis, idempotency_key)
          Rails.logger.info({
            at: "redis.stream.duplicate_skipped",
            idempotency_key: idempotency_key
          }.to_json)
          return :duplicate_skipped
        end

        # Prepare and publish event
        payload = prepare_payload(event_data, idempotency_key)
        message_id = redis.xadd(@stream_name, payload)

        # Ensure consumer group exists
        ensure_consumer_group(redis)

        Rails.logger.info({
          at: "redis.stream.published",
          message_id: message_id,
          idempotency_key: idempotency_key
        }.to_json)

        message_id
      end
    rescue ::Redis::BaseError => e
      Rails.logger.error({
        at: "redis.stream.publish_error",
        error: e.class.name,
        message: e.message,
        idempotency_key: idempotency_key
      }.to_json)
      raise PublishError, "Failed to publish to Redis stream: #{e.message}"
    end

    private

    def duplicate_event?(redis, idempotency_key)
      # Simple check of recent messages (last 100)
      recent_messages = redis.xrevrange(@stream_name, "+", "-", count: 100)
      recent_messages.any? do |_message_id, fields|
        fields_hash = Hash[*fields]
        fields_hash["idempotency_key"] == idempotency_key
      end
    rescue ::Redis::BaseError
      false # If check fails, proceed with publish
    end

    def prepare_payload(event_data, idempotency_key)
      {
        "event_type" => "audio_received",
        "payload" => event_data.to_json,
        "idempotency_key" => idempotency_key,
        "timestamp" => Time.current.iso8601,
        "source" => "lexi-ingestion-api"
      }
    end

    def ensure_consumer_group(redis)
      redis.xgroup(:create, @stream_name, @consumer_group, "$", mkstream: true)
    rescue ::Redis::CommandError => e
      # Ignore if group already exists
      unless e.message.include?("BUSYGROUP")
        Rails.logger.warn("Failed to create consumer group: #{e.message}")
      end
    end
  end
end