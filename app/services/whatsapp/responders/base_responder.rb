# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Whatsapp
  module Responders
    module BaseResponder
      class ApiError < StandardError
        attr_reader :status, :body, :code
        def initialize(message, status: nil, body: nil, code: nil)
          super(message)
          @status = status
          @body   = body
          @code   = code
        end
      end

      # Public: Send a text message to a WhatsApp user and return parsed API response.
      #
      # Params:
      # - to: String (recipient wa_id, e.g. "16505551234")
      # - body: String (message body)
      # - business_number: WaBusinessNumber or String (phone_number_id)
      # - preview_url: Boolean (default: false)
      #
      # Returns parsed JSON response from WhatsApp Graph API.
      def send_text!(to:, body:, business_number:, preview_url: false)
        phone_number_id = if business_number.respond_to?(:phone_number_id)
                            business_number.phone_number_id
                          else
                            business_number.to_s
                          end

        payload = {
          messaging_product: "whatsapp",
          recipient_type: "individual",
          to: to,
          type: "text",
          text: { body: body.to_s, preview_url: !!preview_url }
        }

        path = "/#{phone_number_id}/messages"
        post_graph_json!(path, json: payload)
      end

      # Public: Persist an outbound WaMessage for auditing and state tracking.
      # Returns the created WaMessage record.
      def record_outbound_message!(wa_contact:, wa_business_number:, body:, provider_message_id:, raw: {})
        WaMessage.create!(
          provider_message_id: provider_message_id.to_s,
          direction: "outbound",
          wa_contact: wa_contact,
          wa_business_number: wa_business_number,
          type_name: "text",
          body_text: body.to_s,
          timestamp: Time.current,
          status: "sent",
          has_media: false,
          media_kind: nil,
          raw: raw || {}
        )
      end

      private

      def access_token!
        tok = ENV["INGESTION_WHATSAPP_TOKEN"].to_s
        raise ApiError, "INGESTION_WHATSAPP_TOKEN not configured" if tok.empty?
        tok
      end

      def graph_api_version
        # Reuse MediaApi version if available
        if defined?(Whatsapp::MediaApi::GRAPH_API_VERSION)
          Whatsapp::MediaApi::GRAPH_API_VERSION
        else
          (ENV["GRAPH_API_VERSION"] || "v23.0")
        end
      end

      def http_timeouts
        if defined?(Whatsapp::MediaApi::OPEN_TIMEOUT_S)
          [ Whatsapp::MediaApi::OPEN_TIMEOUT_S, Whatsapp::MediaApi::READ_TIMEOUT_S, Whatsapp::MediaApi::WRITE_TIMEOUT_S ]
        else
          [ (ENV["HTTP_OPEN_TIMEOUT"] || "5").to_i,
            (ENV["HTTP_READ_TIMEOUT"] || "120").to_i,
            (ENV["HTTP_WRITE_TIMEOUT"] || "120").to_i ]
        end
      end

      def post_graph_json!(path, json:)
        uri = URI.parse("https://graph.facebook.com/#{graph_api_version}#{path}")

        open_t, read_t, write_t = http_timeouts
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.open_timeout  = open_t
          http.read_timeout  = read_t
          http.write_timeout = write_t if http.respond_to?(:write_timeout)

          req = Net::HTTP::Post.new(uri)
          req["Authorization"] = "Bearer #{access_token!}"
          req["Content-Type"]  = "application/json"
          req.body = JSON.generate(json)
          http.request(req)
        end

        parsed = parse_json(res)
        return parsed if res.is_a?(Net::HTTPSuccess)

        err = parsed.is_a?(Hash) ? parsed["error"] : nil
        raise ApiError.new(
          err ? "Graph error: #{err["message"]}" : "Graph HTTP #{res.code}",
          status: res.code.to_i,
          body: parsed,
          code: err && err["code"]
        )
      end

      def parse_json(res)
        body = res.body.to_s
        JSON.parse(body)
      rescue JSON::ParserError
        body
      end
    end
  end
end

