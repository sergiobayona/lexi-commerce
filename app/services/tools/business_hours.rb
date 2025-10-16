# frozen_string_literal: true

module Tools
  class BusinessHours < RubyLLM::Tool
    description "Gets the business hours for Tony's Pizza. Can filter by specific day or return all hours."

    param :day, type: :string, required: false,
          desc: "Specific day (monday-sunday) or 'today'. Returns all days if not specified."

    def initialize
      @business_name = "Tony's Pizza"
      @location = "123 Main Street, Brooklyn, NY"
      @phone = "(555) 123-4567"

      # Hard-coded business hours with structured format for parsing
      @hours = {
        monday: { open: "11:00 AM", close: "10:00 PM" },
        tuesday: { open: "11:00 AM", close: "10:00 PM" },
        wednesday: { open: "11:00 AM", close: "10:00 PM" },
        thursday: { open: "11:00 AM", close: "10:00 PM" },
        friday: { open: "11:00 AM", close: "11:00 PM" },
        saturday: { open: "11:00 AM", close: "11:00 PM" },
        sunday: { open: "12:00 PM", close: "9:00 PM" }
      }

      @special_notes = "Closed on Thanksgiving and Christmas Day"
    end

    def execute(day: nil)
      if day.nil?
        return all_hours_info
      end

      requested_day = normalize_day(day)

      unless valid_day?(requested_day)
        return { error: "Invalid day: '#{day}'. Please use monday-sunday or 'today'." }
      end

      day_symbol = requested_day.to_sym
      hours_info = @hours[day_symbol]

      {
        business_name: @business_name,
        location: @location,
        phone: @phone,
        day: requested_day,
        hours: "#{hours_info[:open]} - #{hours_info[:close]}",
        is_today: today?(requested_day),
        current_status: current_status(day_symbol),
        special_notes: @special_notes
      }
    end

    private

    def all_hours_info
      formatted_hours = @hours.transform_values { |h| "#{h[:open]} - #{h[:close]}" }

      {
        business_name: @business_name,
        location: @location,
        phone: @phone,
        hours: formatted_hours,
        current_day: Time.now.strftime("%A").downcase,
        current_time: Time.now.strftime("%I:%M %p"),
        current_status: current_status(Time.now.strftime("%A").downcase.to_sym),
        special_notes: @special_notes
      }
    end

    def normalize_day(day)
      return Time.now.strftime("%A").downcase if day.to_s.downcase == "today"
      day.to_s.downcase.strip
    end

    def valid_day?(day)
      @hours.key?(day.to_sym)
    end

    def today?(day)
      day == Time.now.strftime("%A").downcase
    end

    def current_status(day_symbol)
      return "closed" unless today?(day_symbol.to_s)

      hours_info = @hours[day_symbol]
      return "unknown" unless hours_info

      now = Time.now
      open_time = parse_time(hours_info[:open])
      close_time = parse_time(hours_info[:close])

      if now >= open_time && now <= close_time
        "open"
      else
        "closed"
      end
    rescue StandardError
      "unknown"
    end

    def parse_time(time_string)
      Time.parse(time_string)
    end
  end
end
