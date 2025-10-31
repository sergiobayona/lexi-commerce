# frozen_string_literal: true

module Whatsapp
  # TurnBuilder converts a WaMessage database record into the turn format
  # expected by State::Controller for conversation orchestration.
  #
  # Turn format:
  # {
  #   tenant_id: String,    # Business phone number ID
  #   wa_id: String,        # WhatsApp user ID
  #   message_id: String,   # Unique message identifier
  #   text: String,         # Message text content
  #   payload: Hash/nil,    # Interactive message payload (buttons, etc.)
  #   timestamp: String     # ISO8601 timestamp
  # }
  class TurnBuilder
    def initialize(wa_message)
      @wa_message = wa_message
    end

    def build
      {
        tenant_id: tenant_id,
        wa_id: wa_id,
        message_id: message_id,
        text: extract_text,
        payload: extract_payload,
        timestamp: timestamp
      }
    end

    private

    attr_reader :wa_message

    def tenant_id
      # Use WhatsApp's phone_number_id as stable tenant identifier
      wa_message.wa_business_number.phone_number_id
    end

    def wa_id
      wa_message.wa_contact.wa_id
    end

    def message_id
      wa_message.provider_message_id
    end

    def timestamp
      wa_message.timestamp.iso8601
    end

    # Extract text content based on message type
    def extract_text
      case wa_message.type_name
      when "text"
        wa_message.body_text
      when "audio"
        # For audio, use transcription if available, otherwise placeholder
        wa_message.body_text || "[Audio message]"
      when "button"
        # Extract button response text
        extract_button_text
      when "location"
        format_location
      when "contacts"
        "[Contact card shared]"
      when "document"
        format_document
      when "image", "video", "sticker"
        format_media
      else
        wa_message.body_text || "[#{wa_message.type_name} message]"
      end
    end

    # Extract interactive payload (for buttons, lists, etc.)
    def extract_payload
      case wa_message.type_name
      when "button"
        extract_button_payload
      else
        nil
      end
    end

    def extract_button_text
      # Button messages have the selected button text in body_text
      wa_message.body_text || "[Button response]"
    end

    def extract_button_payload
      # Return button metadata if available
      # This would come from the raw message data stored in wa_message
      # For now, return nil - can be enhanced later
      nil
    end

    def format_location
      # Format location message with coordinates
      # Could include: latitude, longitude, name, address
      "[Location shared]"
    end

    def format_document
      # Format document message with filename
      if wa_message.wa_media&.filename
        "[Document: #{wa_message.wa_media.filename}]"
      else
        "[Document shared]"
      end
    end

    def format_media
      # Format media message with type
      media_type = wa_message.type_name || "media"
      "[#{media_type.capitalize} shared]"
    end
  end
end
