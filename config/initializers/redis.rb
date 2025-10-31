# frozen_string_literal: true

# Redis configuration for outbox event streaming
Rails.application.configure do
  config.redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

  # Configure Redis connection pool
  config.redis_pool_size = ENV.fetch("REDIS_POOL_SIZE", 5).to_i
  config.redis_timeout = ENV.fetch("REDIS_TIMEOUT", 5).to_f

  # Stream configuration
  config.redis_stream_name = ENV.fetch("REDIS_STREAM_NAME", "lexi:audio_events")
  config.redis_consumer_group = ENV.fetch("REDIS_CONSUMER_GROUP", "lexi-speech-worker")
end

# Global Redis connection pool
require "connection_pool"

REDIS_POOL = ConnectionPool.new(size: Rails.application.config.redis_pool_size, timeout: Rails.application.config.redis_timeout) do
  Redis.new(url: Rails.application.config.redis_url)
end
