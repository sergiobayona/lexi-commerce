# frozen_string_literal: true

require "vcr"

VCR.configure do |config|
  # Directory where VCR cassettes (recorded HTTP interactions) will be stored
  config.cassette_library_dir = "spec/vcr_cassettes"

  # Use WebMock for stubbing HTTP requests
  config.hook_into :webmock

  # Allow real HTTP requests to localhost (for test servers)
  config.ignore_localhost = true

  # Configure how VCR matches HTTP requests
  config.default_cassette_options = {
    record: :once,              # Record new interactions only once
    match_requests_on: [
      :method,                  # Match on HTTP method (GET, POST, etc.)
      :uri,                     # Match on full URI
      :body                     # Match on request body
    ],
    allow_unused_http_interactions: false,  # Fail if cassette has unused interactions
    update_content_length_header: true      # Update Content-Length header on playback
  }

  # Filter sensitive data from cassettes
  # WhatsApp access token - replace with placeholder
  config.filter_sensitive_data("<WHATSAPP_TOKEN>") do |interaction|
    if interaction.request.headers["Authorization"]
      interaction.request.headers["Authorization"].first
    end
  end

  # Filter WhatsApp app secret
  config.filter_sensitive_data("<WHATSAPP_APP_SECRET>") do
    ENV["WHATSAPP_APP_SECRET"]
  end

  # Filter WhatsApp verify token
  config.filter_sensitive_data("<WHATSAPP_VERIFY_TOKEN>") do
    ENV["WHATSAPP_VERIFY_TOKEN"]
  end

  # Filter AWS credentials from S3 requests
  config.filter_sensitive_data("<AWS_ACCESS_KEY_ID>") do
    ENV["AWS_ACCESS_KEY_ID"]
  end

  config.filter_sensitive_data("<AWS_SECRET_ACCESS_KEY>") do
    ENV["AWS_SECRET_ACCESS_KEY"]
  end

  # Filter any API keys in query parameters
  config.filter_sensitive_data("<ACCESS_TOKEN>") do |interaction|
    if interaction.request.uri.match(/access_token=([^&]+)/)
      Regexp.last_match(1)
    end
  end

  # Filter phone numbers from WhatsApp API responses (PII protection)
  config.before_record do |interaction|
    # Filter phone numbers in response body
    if interaction.response.body.is_a?(String)
      # Replace phone numbers (format: +1234567890 or 1234567890)
      interaction.response.body.gsub!(/\+?\d{10,15}/, "<PHONE_NUMBER>")
    end

    # Filter phone numbers in request body
    if interaction.request.body.is_a?(String)
      interaction.request.body.gsub!(/\+?\d{10,15}/, "<PHONE_NUMBER>")
    end
  end

  # Configure RSpec metadata for easy cassette usage
  # This provides automatic cassette naming based on test descriptions
  # Usage: it "does something", vcr: true do
  # Usage: it "does something", vcr: { cassette_name: "custom_name" } do
  config.configure_rspec_metadata!

  # Customize cassette naming: use underscores instead of slashes
  config.default_cassette_options[:persister_options] = { file_name: ->(name) { name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "") } }

  # Debug mode - uncomment to see what VCR is doing
  # config.debug_logger = File.open(Rails.root.join("log", "vcr_debug.log"), "w")
end
