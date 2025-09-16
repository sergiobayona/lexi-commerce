# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project
WhatsApp webhook handler for the Lexi language learning pipeline. Processes WhatsApp Business API webhooks and stores message data.

Then main use case is handling whatsapp cloud api webhook payloads:

main end-point:
```api
POST /ingest
```

The `post /ingest` endpoint can handle 2 types of payloads:

1. text messages:
```json
{
  "object": "whatsapp_business_account",
  "entry": [
    {
      "id": "102290129340398",
      "changes": [
        {
          "value": {
            "messaging_product": "whatsapp",
            "metadata": {
              "display_phone_number": "15550783881",
              "phone_number_id": "106540352242922"
            },
            "contacts": [
              {
                "profile": {
                  "name": "Sheena Nelson"
                },
                "wa_id": "16505551234"
              }
            ],
            "messages": [
              {
                "from": "16505551234",
                "id": "wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=",
                "timestamp": "1749416383",
                "type": "text"
                "text": {
                  "body": "Does it come in another color?"
                }
              }
            ]
          },
          "field": "messages"
        }
      ]
    }
  ]
}
```
2. Audio messages:

```json
{
  "object": "whatsapp_business_account",
  "entry": [
    {
      "id": "<WHATSAPP_BUSINESS_ACCOUNT_ID>",
      "changes": [
        {
          "value": {
            "messaging_product": "whatsapp",
            "metadata": {
              "display_phone_number": "<BUSINESS_DISPLAY_PHONE_NUMBER>",
              "phone_number_id": "<BUSINESS_PHONE_NUMBER_ID>"
            },
            "contacts": [
              {
                "profile": {
                  "name": "<WHATSAPP_USER_PROFILE_NAME>"
                },
                "wa_id": "<WHATSAPP_USER_ID>",
                "identity_key_hash": "<IDENTITY_KEY_HASH>" <!-- only included if identity change check enabled -->
              }
            ],
            "messages": [
              {
                "from": "<WHATSAPP_USER_PHONE_NUMBER>",
                "id": "<WHATSAPP_MESSAGE_ID>",
                "timestamp": "<WEBHOOK_TRIGGER_TIMESTAMP>",
                "type": "audio",
                "audio": {
                  "mime_type": "<MEDIA_ASSET_MIME_TYPE>",
                  "sha256": "<MEDIA_ASSET_SHA256_HASH>",
                  "id": "<MEDIA_ASSET_ID>",
                  "voice": <IS_VOICE_RECORDING?>
                },

                <!-- only included if message sent via a Click to WhatsApp ad -->
                "referral": {
                  "source_url": "<AD_URL>",
                  "source_id": "<AD_ID>",
                  "source_type": "ad",
                  "body": "<AD_PRIMARY_TEXT>",
                  "headline": "<AD_HEADLINE>",
                  "media_type": "<AD_MEDIA_TYPE>",
                  "image_url": "<AD_IMAGE_URL>",
                  "video_url": "<AD_VIDEO_URL>",
                  "thumbnail_url": "<AD_VIDEO_THUMBNAIL>",
                  "ctwa_clid": "<AD_CLICK_ID>",
                  "welcome_message": {
                    "text": "<AD_GREETING_TEXT>"
                  }
                }
              }
            ]
          },
          "field": "messages"
        }
      ]
    }
  ]
}
```

## Commands

### Development Setup
```bash
# Install dependencies
bundle install

# Setup database
rails db:create
rails db:migrate

# Start Rails server
rails server
# or
bin/rails s

# Start Sidekiq for background jobs
bundle exec sidekiq

# Rails console
rails console
# or
bin/rails c
```

### Testing
```bash
# Run all specs
rspec

# Run specific test file
rspec spec/path/to/spec_file_spec.rb

# Run with documentation format
rspec --format documentation

# Run with coverage
rspec --coverage
```

### Database Operations
```bash
# Run migrations
rails db:migrate

# Rollback migration
rails db:rollback

# Reset database
rails db:drop db:create db:migrate

# Seed database
rails db:seed
```

### Code Quality
```bash
# Run RuboCop for linting
rubocop

# Auto-fix RuboCop issues
rubocop -A

# Security analysis
brakeman
```

### Background Jobs
```bash
# Start Sidekiq worker
bundle exec sidekiq

# Monitor Sidekiq queue
bundle exec sidekiq -q default

# Clear Sidekiq queue (in console)
Sidekiq::Queue.new.clear
```

## Architecture

### API-Only Rails Application
This is a Rails 8.0 API-only application designed as a WhatsApp webhook ingestion service. It receives WhatsApp messages, stores them, and processes media downloads asynchronously.

### Core Components

**Webhook Controller** (`app/controllers/webhooks_controller.rb`)
- Entry point for WhatsApp webhooks
- Handles webhook verification (GET /ingest)
- Receives webhook payloads (POST /ingest)
- Validates signatures and queues processing jobs

**Background Processing**
- Uses Sidekiq with Redis for job queuing
- `Whatsapp::IngestWebhookJob`: Processes incoming webhook payloads
- `Media::DownloadJob`: Downloads media files from WhatsApp to S3

**WhatsApp Media API Service** (`app/services/whatsapp/media_api.rb`)
- Handles authenticated requests to WhatsApp Graph API
- Downloads media files with retry logic and streaming
- Uploads directly to S3 without local buffering
- Includes SHA256 verification for file integrity

**Message Processing Pipeline**
1. Webhook receives payload → stored in `webhook_events` table
2. `IngestWebhookJob` processes the event asynchronously
3. Messages are parsed and stored with relationships:
   - `wa_contacts`: WhatsApp user information
   - `wa_business_numbers`: Business phone numbers
   - `wa_messages`: Message content and metadata
   - `wa_media`: Media file references
4. Audio messages trigger `AudioProcessor` for specialized handling
5. Media files are downloaded to S3 via streaming

### Database Schema
- **webhook_events**: Raw webhook payloads (JSONB)
- **wa_messages**: Core message data with provider_message_id as unique key
- **wa_contacts**: WhatsApp contacts (users)
- **wa_business_numbers**: Business phone numbers
- **wa_media**: Media file metadata and S3 references
- **wa_message_media**: Join table for messages and media
- **wa_message_status_events**: Message delivery status updates
- **wa_referrals**: Referral tracking

### Service Layer Pattern
- **Processors**: Handle specific message types (audio, text)
- **Upserters**: Manage database upserts with conflict resolution
- **MediaAPI**: External API interactions with retry logic

### Configuration

**Environment Variables Required**:
- `WHATSAPP_TOKEN`: WhatsApp API access token
- `WHATSAPP_APP_SECRET`: For webhook signature verification
- `WHATSAPP_VERIFY_TOKEN`: For webhook verification
- `S3_BUCKET`: S3 bucket for media storage
- `S3_REGION`: AWS region for S3
- `DATABASE_URL`: PostgreSQL connection (production)
- `REDIS_URL`: Redis connection for Sidekiq

**Storage**: Uses Active Storage with S3 for media files

**Queue System**: Solid Queue (database-backed) and Sidekiq (Redis-backed) configured

### Key Design Decisions

1. **Streaming Media Downloads**: Files are streamed directly from WhatsApp to S3 without local storage, preventing memory issues with large files

2. **Webhook Idempotency**: Uses `provider_message_id` as unique constraint to handle duplicate webhooks

3. **JSONB Storage**: Raw webhook payloads stored in JSONB for debugging and replay capabilities

4. **Modular Processors**: Separate processor classes for different message types allow easy extension

5. **Retry Logic**: HTTP requests include exponential backoff with jitter for resilience