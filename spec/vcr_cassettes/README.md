# VCR Cassettes

This directory contains recorded HTTP interactions for testing. VCR records real HTTP requests the first time a test runs, then replays them on subsequent runs.

## Benefits

- **Fast tests**: No actual HTTP requests after initial recording
- **Deterministic**: Tests always get the same responses
- **Offline testing**: No internet connection needed
- **Cost savings**: No API charges for replayed requests
- **Debugging**: Cassettes can be inspected to understand API interactions

## Usage

### Basic Usage (Automatic Cassette Naming)

Tag your spec with `:vcr` to automatically record/replay HTTP interactions:

```ruby
RSpec.describe Whatsapp::MediaApi, :vcr do
  it "downloads media from WhatsApp" do
    media_api = Whatsapp::MediaApi.new
    media_api.download_media("media_id_123")
  end
end
```

Cassette will be saved as: `whatsapp_media_api_downloads_media_from_whatsapp.yml`

### Custom Cassette Name

Specify a custom cassette name for better organization:

```ruby
it "handles large files", vcr: { cassette_name: "whatsapp/large_media_download" } do
  # Test code
end
```

### Per-Example Recording Options

Override default options for specific tests:

```ruby
it "always re-records", vcr: { record: :all } do
  # This will always make a real request and update the cassette
end

it "records new interactions", vcr: { record: :new_episodes } do
  # Records any new HTTP interactions not in the cassette
end
```

### Grouping Cassettes by Context

Use `describe` or `context` blocks with VCR:

```ruby
describe "WhatsApp Media API", :vcr do
  context "with valid media ID" do
    it "downloads successfully" do
      # Uses: whatsapp_media_api_with_valid_media_id_downloads_successfully.yml
    end
  end

  context "with invalid media ID" do
    it "raises an error" do
      # Uses: whatsapp_media_api_with_invalid_media_id_raises_an_error.yml
    end
  end
end
```

## Recording Modes

VCR supports different recording modes:

- `:once` (default) - Record new cassettes, but reuse existing ones
- `:new_episodes` - Record new interactions, keep existing ones
- `:all` - Always make real requests and overwrite cassettes
- `:none` - Never make real requests (cassette must exist)

## Sensitive Data Protection

The VCR configuration automatically filters sensitive data:

### Automatically Filtered
- WhatsApp access tokens (in Authorization header)
- WhatsApp app secret
- WhatsApp verify token
- AWS credentials (access key, secret key)
- Phone numbers (PII protection)
- Access tokens in query parameters

### Reviewing Cassettes

**IMPORTANT**: Always review cassettes before committing to ensure no sensitive data is leaked:

```bash
# Check for potential leaks
grep -r "access_token" spec/vcr_cassettes/
grep -r "Bearer " spec/vcr_cassettes/
grep -r "@" spec/vcr_cassettes/  # Email addresses
```

## Managing Cassettes

### Re-recording Cassettes

When API responses change, you need to re-record:

```bash
# Delete specific cassette
rm spec/vcr_cassettes/whatsapp_media_api_downloads_media.yml

# Delete all cassettes
rm -rf spec/vcr_cassettes/*.yml

# Re-run tests to record new cassettes
bundle exec rspec
```

### Updating a Single Cassette

```ruby
# Temporarily change record mode in the spec
it "downloads media", vcr: { record: :all } do
  # Test code
end

# Run just this test
# bundle exec rspec spec/path/to/spec.rb:LINE_NUMBER

# Change back to default after recording
it "downloads media", vcr: true do
  # Test code
end
```

## Best Practices

### 1. Use Descriptive Test Names

Cassette names are derived from test descriptions:

```ruby
# Good - creates meaningful cassette name
it "downloads audio file from WhatsApp media API" do
  # whatsapp_media_api_downloads_audio_file_from_whatsapp_media_api.yml
end

# Bad - creates unclear cassette name
it "works" do
  # whatsapp_media_api_works.yml
end
```

### 2. Organize by Service

Use custom names to organize by external service:

```ruby
describe "WhatsApp API" do
  it "fetches media", vcr: { cassette_name: "whatsapp/media_fetch" } do
  end

  it "sends message", vcr: { cassette_name: "whatsapp/message_send" } do
  end
end
```

### 3. Test Edge Cases

Record cassettes for different scenarios:

```ruby
context "successful request" do
  it "returns media data", vcr: true do
  end
end

context "API errors" do
  it "handles 404 not found", vcr: { cassette_name: "whatsapp/media_not_found" } do
  end

  it "handles rate limiting", vcr: { cassette_name: "whatsapp/rate_limited" } do
  end
end
```

### 4. Keep Cassettes Small

Avoid recording unnecessary requests:

```ruby
# Setup data without recording
before do
  VCR.turned_off do
    # Setup code that doesn't need recording
    WebMock.allow_net_connect!
    setup_test_data
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
```

### 5. Version Control

- **DO** commit cassettes to git (they're part of your test suite)
- **DO** review cassettes in PR reviews
- **DON'T** commit cassettes with real credentials or PII
- **DON'T** commit excessively large cassettes (>1MB)

## Troubleshooting

### Cassette Doesn't Match Request

**Problem**: Test fails with "VCR could not find a cassette to use"

**Solution**: The request being made doesn't match the recorded one. Common causes:

1. **Different body**: Request body changed
   ```ruby
   # Use more flexible matching
   it "test", vcr: { match_requests_on: [:method, :uri] } do
   ```

2. **Timestamp in request**: Dynamic data in request
   ```ruby
   # Ignore specific headers
   VCR.use_cassette("test", match_requests_on: [:method, :uri]) do
   end
   ```

3. **Different query parameters**: Parameter order changed
   ```ruby
   # Record new cassette
   it "test", vcr: { record: :all } do
   ```

### Real Requests Still Being Made

**Problem**: VCR isn't intercepting requests

**Solution**:
1. Ensure test is tagged with `:vcr`
2. Check WebMock is loaded: `require 'webmock'` in spec
3. Verify service is not in `ignore_hosts` list

### Cassette Contains Sensitive Data

**Problem**: Accidentally committed credentials

**Solution**:
1. Remove cassette from git history:
   ```bash
   git filter-branch --force --index-filter \
     'git rm --cached --ignore-unmatch spec/vcr_cassettes/sensitive.yml' \
     --prune-empty --tag-name-filter cat -- --all
   ```

2. Add to `.gitignore` if needed
3. Update VCR filters in `spec/support/vcr.rb`
4. Re-record with proper filtering

## Examples

### Testing WhatsApp Media Download

```ruby
require "rails_helper"

RSpec.describe Whatsapp::MediaApi do
  describe "#download_media" do
    let(:media_api) { described_class.new }
    let(:media_id) { "test_media_123" }

    it "downloads media successfully", vcr: { cassette_name: "whatsapp/media_download_success" } do
      result = media_api.download_media(media_id)

      expect(result).to be_success
      expect(result.content_type).to eq("audio/ogg")
    end

    it "handles not found error", vcr: { cassette_name: "whatsapp/media_not_found" } do
      expect {
        media_api.download_media("invalid_id")
      }.to raise_error(Whatsapp::MediaApi::NotFoundError)
    end
  end
end
```

### Testing with Multiple Services

```ruby
RSpec.describe "Order Processing", :vcr do
  it "processes order with payment and notification" do
    # This test might hit multiple services:
    # - Payment API
    # - Notification API
    # - Inventory API
    # All interactions are recorded in one cassette
    order = create(:order)
    OrderProcessor.new(order).process

    expect(order.reload).to be_paid
  end
end
```

## Configuration

VCR configuration is in [spec/support/vcr.rb](../support/vcr.rb).

Key settings:
- **Cassette library**: `spec/vcr_cassettes/`
- **Default record mode**: `:once`
- **Request matching**: `[:method, :uri, :body]`
- **Ignore localhost**: `true` (allows test server requests)

## Resources

- [VCR Documentation](https://benoittgt.github.io/vcr/)
- [WebMock Documentation](https://github.com/bblimke/webmock)
- [RSpec Integration](https://benoittgt.github.io/vcr/rspec/)
