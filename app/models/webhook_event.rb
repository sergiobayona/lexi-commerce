class WebhookEvent < ApplicationRecord
  validates :provider, presence: true
  validates :payload, presence: true
end
