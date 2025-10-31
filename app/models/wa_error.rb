class WaError < ApplicationRecord
  # Associations
  belongs_to :wa_message, optional: true
  belongs_to :webhook_event, optional: true

  # Enums
  enum :error_type, {
    system: "system",       # System/app/account-level errors (entry.changes.value.errors)
    message: "message",     # Incoming message errors (entry.changes.value.messages.errors)
    status: "status"        # Outgoing message status errors (entry.changes.value.statuses.errors)
  }, validate: true

  enum :error_level, {
    error: "error",
    warning: "warning",
    info: "info"
  }, validate: true

  # Validations
  validates :error_type, presence: true
  validates :error_level, presence: true
  validates :raw_error_data, presence: true

  # Scopes
  scope :unresolved, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(error_type: type) }
  scope :by_level, ->(level) { where(error_level: level) }
  scope :critical, -> { where(error_level: "error") }

  # Instance methods
  def resolve!(notes = nil)
    update!(
      resolved: true,
      resolved_at: Time.current,
      resolution_notes: notes
    )
  end

  def error_summary
    [ error_code, error_title, error_message ].compact.join(" - ")
  end
end
