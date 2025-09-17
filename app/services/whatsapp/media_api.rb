# frozen_string_literal: true

require "net/http"
require "uri"
require "cgi"
require "json"
require "openssl"
require "digest"

module Whatsapp
  module MediaApi
    class Error < StandardError
      attr_reader :status, :body, :code
      def initialize(message, status: nil, body: nil, code: nil)
        super(message)
        @status = status
        @body   = body
        @code   = code
      end
    end

    GRAPH_API_VERSION = (ENV["GRAPH_API_VERSION"] || "v23.0").freeze
    OPEN_TIMEOUT_S    = (ENV["HTTP_OPEN_TIMEOUT"] || "5").to_i
    READ_TIMEOUT_S    = (ENV["HTTP_READ_TIMEOUT"] || "120").to_i
    WRITE_TIMEOUT_S   = (ENV["HTTP_WRITE_TIMEOUT"] || "120").to_i
    RETRIES           = (ENV["HTTP_RETRIES"] || "3").to_i
    RETRY_BASE_MS     = (ENV["HTTP_RETRY_BASE_MS"] || "200").to_i

    class << self
      # Look up a media URL (short-lived), plus best-effort filename, mime_type, and file_size.
      # Returns [url, filename, mime_type, file_size]
      def lookup(media_id)
        token = access_token!
        json  = graph_get_json("/#{media_id}", params: { fields: "url,mime_type,sha256,file_size" }, token:)

        url        = json["url"] or raise Error.new("Graph lookup returned no URL", status: 200, body: json)
        mime_type  = json["mime_type"]
        file_size  = json["file_size"]
        filename   = nil

        # HEAD the URL to refine filename/mime/size (URL expires quickly; do this right before download).
        head_info = head(url)
        filename  = head_info[:filename] if head_info[:filename]
        mime_type = head_info[:content_type] if head_info[:content_type] && mime_type.to_s.empty?
        file_size = head_info[:content_length] if head_info[:content_length] && file_size.to_s.empty?

        [ url, filename, mime_type, file_size ]
      end

      # Stream a short-lived media URL directly into S3 without buffering the whole file.
      # Returns { bytes:, sha256: }
      def stream_to_s3(url, key, expected_sha256: nil, bucket: ENV["S3_BUCKET"], region: ENV["S3_REGION"], content_type: nil)
        raise Error, "S3 bucket not configured" if bucket.to_s.empty?

        require "aws-sdk-s3"
        require "tempfile"

        Rails.logger.info("Starting media download from WhatsApp: #{url[0..100]}...")

        s3_client = Aws::S3::Client.new(region: region.presence)

        bytes_count = 0
        sha = Digest::SHA256.new

        # Get content_type if not provided
        ct = content_type || head(url)[:content_type]

        # Use a temporary file to avoid stream threading issues
        Tempfile.create([ "wa-media", Whatsapp::MediaApi.extension_for(ct) ]) do |temp_file|
          # Download to temp file while calculating SHA256
          begin
            download(url) do |chunk|
              temp_file.write(chunk)
              sha.update(chunk)
              bytes_count += chunk.bytesize
            end
          rescue Error => e
            Rails.logger.error("Failed to download media from WhatsApp: #{e.message}")
            Rails.logger.error("Status: #{e.status}, Body: #{e.body&.to_s&.[](0..500)}")
            raise
          end

          # Ensure all data is written and seek to beginning
          temp_file.flush
          temp_file.rewind

          Rails.logger.info("Downloaded #{bytes_count} bytes, uploading to S3: #{bucket}/#{key}")

          # Upload to S3 from temp file
          s3_client.put_object(
            bucket: bucket,
            key: key,
            body: temp_file,
            content_type: ct,
            acl: "private",
            metadata: { "sha256" => sha.hexdigest }
          )
        end

        computed = sha.hexdigest
        if expected_sha256.present? && expected_sha256.downcase != computed.downcase
          # Delete the uploaded object if integrity check fails
          begin
            s3_client.delete_object(bucket: bucket, key: key)
          rescue => _
            # non-fatal
          end
          raise Error, "SHA256 mismatch (expected #{expected_sha256}, got #{computed})"
        end

        Rails.logger.info("Successfully uploaded media to S3: #{key} (#{bytes_count} bytes, SHA256: #{computed})")
        { bytes: bytes_count, sha256: computed }
      end

      # Convenience: do everything in one call starting from media_id.
      # Returns { key:, bytes:, sha256:, mime_type:, filename: }
      def download_to_s3_by_media_id(media_id, key_prefix: "wa/", max_retries: 2)
        retries = 0
        begin
          url, filename, mime_type, _size = lookup(media_id)
          ext = extension_for(mime_type)
          key = "#{key_prefix}#{media_id}#{ext}"

          res = stream_to_s3(url, key, content_type: mime_type)
          { key:, bytes: res[:bytes], sha256: res[:sha256], mime_type:, filename: filename }
        rescue Error => e
          # Retry if URL expired (401/403 errors)
          if (e.status == 401 || e.status == 403) && retries < max_retries
            retries += 1
            Rails.logger.warn("Media URL expired or unauthorized (attempt #{retries}/#{max_retries}), fetching new URL for media_id: #{media_id}")
            sleep(0.5 * retries) # Brief delay before retry
            retry
          else
            raise
          end
        end
      end

      # Map MIME types to preferred file extensions.
      def extension_for(mime_type)
        return "" if mime_type.to_s.empty?
        mt = mime_type.to_s.downcase.split(";").first.strip
        case mt
        when "audio/ogg"       then ".ogg"
        when "audio/mpeg"      then ".mp3"
        when "audio/wav", "audio/x-wav" then ".wav"
        when "audio/mp4"       then ".m4a"
        when "audio/aac"       then ".aac"
        when "audio/webm"      then ".webm"
        when "audio/3gpp"      then ".3gp"
        when "audio/amr"       then ".amr"
        when "audio/opus"      then ".opus"  # rare direct type; often comes via audio/ogg
        else ""
        end
      end

      private

      # ---- HTTP helpers ----

      def access_token!
        tok = ENV["INGESTION_WHATSAPP_TOKEN"].to_s
        raise Error, "INGESTION_WHATSAPP_TOKEN not configured" if tok.empty?
        tok
      end

      def graph_get_json(path, params:, token:)
        uri = URI.parse("https://graph.facebook.com/#{GRAPH_API_VERSION}#{path}")
        q = URI.decode_www_form(uri.query.to_s) + params.to_a
        uri.query = URI.encode_www_form(q)

        with_retries do
          res = http_request(uri) do |http|
            req = Net::HTTP::Get.new(uri)
            req["Authorization"] = "Bearer #{token}"
            http.request(req)
          end
          parse_graph_json!(res)
        end
      end

      def head(url)
        uri = URI.parse(url)
        res = with_retries do
          http_request(uri) do |http|
            req = Net::HTTP::Head.new(uri)
            http.request(req)
          end
        end
        unless res.is_a?(Net::HTTPSuccess)
          # Some CDNs disallow HEAD; fall back to GET first bytes
          res = with_retries do
            http_request(uri) do |http|
              req = Net::HTTP::Get.new(uri)
              req["Range"] = "bytes=0-0"
              http.request(req)
            end
          end
        end

        headers = downcase_headers(res)
        {
          content_type: headers["content-type"],
          content_length: (headers["content-length"]&.to_i),
          filename: parse_filename(headers["content-disposition"])
        }
      rescue => _
        { content_type: nil, content_length: nil, filename: nil }
      end

      # Stream download; yields chunks to the given block
      def download(url, &block)
        raise ArgumentError, "block required" unless block_given?
        uri = URI.parse(url)
        res = with_retries do
          http_request(uri) do |http|
            req = Net::HTTP::Get.new(uri)

            # WhatsApp media URLs require Authorization header with access token
            # Even though the URL has an access_token query param, the header is also required
            if uri.host&.include?(".fbcdn.net") || uri.host&.include?("lookaside.fbsbx.com")
              req["Authorization"] = "Bearer #{access_token!}"
              Rails.logger.debug("Adding Authorization header for WhatsApp media download from #{uri.host}")
            end

            http.request(req) do |r|
              unless r.is_a?(Net::HTTPSuccess)
                body = r.body.to_s[0..500] # Truncate body for logging
                Rails.logger.error("WhatsApp Media download failed: HTTP #{r.code} - #{r.message}. URL: #{uri}, Body: #{body}")

                # If we get a 401/403, it might be an expired URL (5-minute validity)
                if r.code.to_i == 401 || r.code.to_i == 403
                  raise Error.new("Media URL may have expired (URLs are only valid for 5 minutes) or token is invalid: HTTP #{r.code}", status: r.code.to_i, body: r.body)
                else
                  raise Error.new("Download failed: HTTP #{r.code} - #{r.message}", status: r.code.to_i, body: r.body)
                end
              end
              r.read_body(&block)
              r
            end
          end
        end
        res
      end

      def http_request(uri)
        limit = 5
        current_uri = uri

        limit.times do
          res = Net::HTTP.start(current_uri.host, current_uri.port,
                                use_ssl: current_uri.scheme == "https") do |http|
            http.open_timeout  = OPEN_TIMEOUT_S
            http.read_timeout  = READ_TIMEOUT_S
            http.write_timeout = WRITE_TIMEOUT_S if http.respond_to?(:write_timeout)
            yield(http)
          end

          if res.is_a?(Net::HTTPRedirection) && (loc = res["location"]).present?
            current_uri = URI.parse(loc)
            next
          end

          return res
        end

        raise Error, "Too many redirects"
      end

      def with_retries
        attempts = 0
        begin
          attempts += 1
          yield
        rescue Error => e
          if retriable_status?(e.status) && attempts <= RETRIES
            sleep(backoff_ms(attempts) / 1000.0)
            retry
          end
          raise
        rescue Timeout::Error, IOError, Errno::ECONNRESET, Errno::ETIMEDOUT => e
          if attempts <= RETRIES
            sleep(backoff_ms(attempts) / 1000.0)
            retry
          end
          raise Error.new("HTTP error: #{e.class}: #{e.message}")
        end
      end

      def retriable_status?(status)
        return false unless status
        status.to_i == 429 || (500..599).include?(status.to_i)
      end

      def backoff_ms(attempt)
        # exponential backoff with jitter
        base = RETRY_BASE_MS * (2 ** (attempt - 1))
        jitter = rand(0..RETRY_BASE_MS)
        base + jitter
      end

      def parse_graph_json!(res)
        status = res.code.to_i
        body   = res.body.to_s

        begin
          json = (defined?(Oj) ? Oj.load(body) : JSON.parse(body))
        rescue JSON::ParserError
          raise Error.new("Graph returned non-JSON", status:, body:)
        end

        if res.is_a?(Net::HTTPSuccess)
          return json
        end

        if json.is_a?(Hash) && json["error"]
          err = json["error"]
          raise Error.new("Graph error: #{err["message"]}", status:, body:, code: err["code"])
        end

        raise Error.new("Graph HTTP #{status}", status:, body:)
      end

      def downcase_headers(res)
        res.each_header.to_h.transform_keys { |k| k.to_s.downcase }
      end

      def parse_filename(content_disposition)
        return nil if content_disposition.to_s.empty?
        # Content-Disposition: attachment; filename="foo.ogg"
        cd = content_disposition
        if (m = cd.match(/filename\*?=(?:UTF-8'')?"?([^\";]+)"?/i))
          filename = CGI.unescape(m[1].to_s)
          return filename unless filename.empty?
        end
        nil
      end
    end
  end
end
