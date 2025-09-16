# app/services/whats_app/upserters.rb
module Whatsapp
  module Upserters
    def upsert_business_number!(metadata)
      WaBusinessNumber.upsert(
        { phone_number_id: metadata["phone_number_id"],
          display_phone_number: metadata["display_phone_number"],
          created_at: Time.current, updated_at: Time.current },
        unique_by: :index_wa_business_numbers_on_phone_number_id
      )
      WaBusinessNumber.find_by!(phone_number_id: metadata["phone_number_id"])
    end

    def upsert_contact!(contact_hash)
      return nil unless contact_hash
      rec = WaContact.find_or_initialize_by(wa_id: contact_hash["wa_id"])
      rec.profile_name = contact_hash.dig("profile", "name") if contact_hash.dig("profile", "name").present?
      if (idh = contact_hash["identity_key_hash"]).present? && idh != rec.identity_key_hash
        rec.identity_key_hash = idh
        rec.identity_last_changed_at = Time.current
      end
      rec.first_seen_at ||= Time.current
      rec.last_seen_at = Time.current
      rec.save!
      rec
    end

    def upsert_message!(attrs)
      WaMessage.upsert(attrs, unique_by: :index_wa_messages_on_provider_message_id)
      WaMessage.find_by!(provider_message_id: attrs[:provider_message_id])
    end

    def upsert_media!(attrs)
      WaMedia.upsert(
        attrs.merge(download_status: "pending", created_at: Time.current, updated_at: Time.current),
        unique_by: :index_wa_media_on_provider_media_id
      )
      WaMedia.find_by!(provider_media_id: attrs[:provider_media_id])
    end
  end
end
