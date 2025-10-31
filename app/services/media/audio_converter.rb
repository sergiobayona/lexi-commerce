require "av"

module Media
  class AudioConverter
    class ConversionError < StandardError; end

    # Convert audio file to WAV format (16kHz, mono, PCM signed 16-bit little endian)
    # Required for Whisper transcription
    #
    # @param input_path [String] Path to the input audio file
    # @return [String] Path to the converted WAV file
    # @raise [ArgumentError] if input file doesn't exist
    # @raise [ConversionError] if conversion fails
    def self.to_wav(input_path)
      new(input_path).convert_to_wav
    end

    def initialize(input_path)
      @input_path = input_path
      validate_input!
    end

    def convert_to_wav
      output_path = @input_path.sub(/\.\w+$/, ".wav")

      Rails.logger.info("Converting audio to WAV: #{@input_path} -> #{output_path}")

      # Use av gem (FFmpeg C bindings) to convert audio
      # Options:
      # ar: Sample rate 16kHz
      # ac: Mono audio (1 channel)
      # acodec: PCM signed 16-bit little endian codec
      cli = Av.cli
      cli.add_source(@input_path)
      cli.add_destination(output_path) do |dest|
        dest.ar = 16000       # Sample rate: 16kHz
        dest.ac = 1           # Audio channels: mono
        dest.acodec = "pcm_s16le"  # Codec: PCM signed 16-bit little endian
      end

      cli.run

      validate_output!(output_path)

      Rails.logger.info("Successfully converted audio to WAV: #{output_path}")

      output_path
    rescue => e
      Rails.logger.error("Failed to convert audio to WAV: #{e.class} - #{e.message}")
      raise ConversionError, "Audio conversion failed: #{e.message}"
    end

    private

    def validate_input!
      raise ArgumentError, "Input file does not exist: #{@input_path}" unless File.exist?(@input_path)
    end

    def validate_output!(output_path)
      return if File.exist?(output_path)

      error_message = "Conversion completed but output file not found: #{output_path}"
      Rails.logger.error(error_message)
      raise ConversionError, error_message
    end
  end
end
