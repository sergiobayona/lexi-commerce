# app/models/wa_media.rb
class WaMedia < ApplicationRecord
  enum :download_status, { pending: "pending", downloading: "downloading", downloaded: "downloaded", failed: "failed" }, prefix: true
  has_many :wa_message_media, dependent: :destroy
  has_many :messages, through: :wa_message_media, source: :message

  validates :provider_media_id, presence: true, uniqueness: true
  validates :sha256, presence: true, uniqueness: true
end
