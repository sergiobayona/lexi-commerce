FactoryBot.define do
  factory :wa_message do
    provider_message_id { "MyString" }
    direction { "MyString" }
    from_wa_contact { nil }
    to_business_number { nil }
    type_name { "MyString" }
    body_text { "MyText" }
    timestamp { "2025-09-16 10:35:12" }
    status { "MyString" }
    context_msg_id { "MyString" }
    has_media { false }
    media_kind { "MyString" }
    wa_contact_snapshot { "" }
    metadata_snapshot { "" }
    raw { "" }
  end
end
