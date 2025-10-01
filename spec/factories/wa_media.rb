FactoryBot.define do
  factory :wa_medium, aliases: [:wa_media], class: 'WaMedia' do
    provider_media_id { "MyString" }
    sha256 { "MyString" }
    mime_type { "MyString" }
    is_voice { false }
    bytes { "" }
    storage_url { "MyString" }
    download_status { "MyString" }
    last_error { "MyText" }
  end
end
