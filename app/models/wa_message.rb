class WaMessage < ApplicationRecord
  self.inheritance_column = :_type_disabled
  enum :direction, { inbound: "inbound", outbound: "outbound" }, prefix: true
  enum :media_kind, { audio: "audio", image: "image", video: "video", document: "document", sticker: "sticker", unknown: "unknown" }, prefix: true

  belongs_to :wa_contact, class_name: "WaContact", optional: true
  belongs_to :wa_business_number, class_name: "WaBusinessNumber"
  has_one :wa_message_media, dependent: :destroy
  has_one :media, through: :wa_message_media, source: :media
  has_one :referral, class_name: "WaReferral", dependent: :destroy

  validates :provider_message_id, presence: true, uniqueness: true
  validates :timestamp, presence: true
end
