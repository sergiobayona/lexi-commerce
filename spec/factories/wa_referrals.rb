FactoryBot.define do
  factory :wa_referral do
    message { nil }
    source_url { "MyString" }
    source_id { "MyString" }
    source_type { "MyString" }
    body { "MyText" }
    headline { "MyText" }
    media_type { "MyString" }
    image_url { "MyString" }
    video_url { "MyString" }
    thumbnail_url { "MyString" }
    ctwa_clid { "MyString" }
    welcome_message_json { "" }
  end
end
