module Whatsapp
  module Processors
    class TextProcessor < BaseProcessor
      def call
        number  = upsert_business_number!(@value["metadata"])
        contact = upsert_contact!(@value["contacts"]&.first)
        attrs   = common_message_attrs(number, contact).merge(
          type_name: "text",
          has_media: false,
          media_kind: nil
        )
        msg = upsert_message!(attrs)
        msg.update!(body_text: @msg.dig("text", "body"))
        msg
      end
    end
  end
end
