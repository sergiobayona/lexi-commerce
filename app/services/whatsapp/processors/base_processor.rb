module Whatsapp
  module Processors
    class BaseProcessor
      include Whatsapp::Upserters

      def initialize(value, msg)
        @value = value
        @msg = msg
      end

      def call
        # default no-op or unknown-type handling
      end

      protected
      def common_message_attrs(number, contact)
        {
          provider_message_id: @msg["id"],
          direction: "inbound",
          wa_contact_id: contact&.id,
          wa_business_number_id: number.id,
          timestamp: Time.at(@msg["timestamp"].to_i).utc,
          status: "received",
          metadata_snapshot: @value["metadata"],
          wa_contact_snapshot: (@value["contacts"]&.first || {}),
          raw: @msg
        }
      end
    end
  end
end
