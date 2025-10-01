FactoryBot.define do
  factory :wa_error do
    error_type { "system" }
    error_level { "error" }
    error_code { 100 }
    error_title { "API Error" }
    error_message { "An error occurred" }
    error_details { nil }
    provider_message_id { nil }
    raw_error_data { { "code" => 100, "title" => "API Error" } }
    resolved { false }

    trait :system_error do
      error_type { "system" }
      error_code { 131047 }
      error_title { "Service unavailable" }
      error_message { "Service temporarily unavailable. Please retry your request" }
    end

    trait :message_error do
      error_type { "message" }
      error_code { 131051 }
      error_title { "Unsupported message type" }
      error_message { "Message type is not currently supported" }
      provider_message_id { "wamid.unsupported123" }
    end

    trait :status_error do
      error_type { "status" }
      error_code { 131026 }
      error_title { "Message undeliverable" }
      error_message { "Message failed to send" }
      provider_message_id { "wamid.failed123" }
    end

    trait :resolved do
      resolved { true }
      resolved_at { Time.current }
      resolution_notes { "Issue resolved by team" }
    end

    trait :warning do
      error_level { "warning" }
    end

    trait :info do
      error_level { "info" }
    end
  end
end
