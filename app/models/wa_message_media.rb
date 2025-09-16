class WaMessageMedia < ApplicationRecord
  belongs_to :wa_message
  belongs_to :wa_media
end
