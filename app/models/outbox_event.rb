# frozen_string_literal: true

class OutboxEvent < ApplicationRecord
  validates :event_type, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[pending processing processed failed] }
  validates :payload, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :processed, -> { where(status: "processed") }
  scope :failed, -> { where(status: "failed") }
  scope :for_retry, -> { where(status: "failed").where("retry_count < ?", max_retries) }

  MAX_RETRIES = 3

  def self.max_retries
    MAX_RETRIES
  end

  def mark_processing!
    update!(status: "processing")
  end

  def mark_processed!
    update!(
      status: "processed",
      processed_at: Time.current,
      last_error: nil
    )
  end

  def mark_failed!(error_message)
    update!(
      status: "failed",
      retry_count: retry_count + 1,
      last_error: error_message
    )
  end

  def can_retry?
    retry_count < self.class.max_retries
  end

  def audio_received?
    event_type == "audio_received"
  end
end