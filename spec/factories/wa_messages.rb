FactoryBot.define do
  factory :wa_message do
    provider_message_id { "wamid.#{SecureRandom.hex(8)}" }
    direction { "inbound" }
    association :wa_contact
    association :wa_business_number
    type_name { "text" }
    body_text { "Sample message" }
    timestamp { Time.current }
    status { "received" }
    context_msg_id { nil }
    has_media { false }
    media_kind { nil }
    wa_contact_snapshot { {} }
    metadata_snapshot { {} }
    raw { {} }

    trait :with_audio do
      type_name { "audio" }
      has_media { true }
      media_kind { "audio" }
    end

    trait :outbound do
      direction { "outbound" }
      status { "sent" }
    end
  end
end
