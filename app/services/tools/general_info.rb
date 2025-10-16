module Tools
  # GeneralInfoTools provides tools for fetching general information like weather
  class GeneralInfo
    def self.all
      [ BusinessHours, Locations, GeneralFaq ]
    end
  end

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

  class Locations < RubyLLM::Tool
    description "Search for Tony's Pizza locations by name, city, or find nearest location to coordinates"

    param :search, type: :string, required: false,
          desc: "Location name or city to search for (e.g., 'Brooklyn', 'Manhattan')"
    param :latitude, type: :number, required: false,
          desc: "Latitude for proximity search (must provide both latitude and longitude)"
    param :longitude, type: :number, required: false,
          desc: "Longitude for proximity search (must provide both latitude and longitude)"

    def initialize
      @locations = [
        {
          name: "Tony's Pizza - Brooklyn",
          address: "123 Main Street, Brooklyn, NY 11201",
          phone: "(555) 123-4567",
          email: "brooklyn@tonyspizza.com",
          features: [
            "Dine-in",
            "Takeout",
            "Delivery",
            "Outdoor seating",
            "Free WiFi",
            "Family friendly"
          ],
          parking: "Street parking available",
          accessibility: "Wheelchair accessible",
          coordinates: {
            latitude: 40.6782,
            longitude: -73.9442
          }
        },
        {
          name: "Tony's Pizza - Manhattan",
          address: "456 Broadway, New York, NY 10013",
          phone: "(555) 987-6543",
          email: "manhattan@tonyspizza.com",
          features: [
            "Dine-in",
            "Takeout",
            "Delivery",
            "Bar service",
            "Private events",
            "Free WiFi"
          ],
          parking: "Parking garage nearby (paid)",
          accessibility: "Wheelchair accessible",
          coordinates: {
            latitude: 40.7589,
            longitude: -73.9851
          }
        }
      ]
    end

    def execute(search: nil, latitude: nil, longitude: nil)
      # Validation for coordinate parameters
      if (latitude && !longitude) || (!latitude && longitude)
        return { error: "Both latitude and longitude are required for proximity search" }
      end

      if latitude && (latitude < -90 || latitude > 90)
        return { error: "Latitude must be between -90 and 90" }
      end

      if longitude && (longitude < -180 || longitude > 180)
        return { error: "Longitude must be between -180 and 180" }
      end

      # Proximity search
      if latitude && longitude
        return proximity_search(latitude, longitude)
      end

      # Text search
      if search.present?
        return text_search(search)
      end

      # No parameters - return all locations
      {
        total_locations: @locations.length,
        locations: @locations
      }
    rescue StandardError => e
      Rails.logger.error "Location search failed: #{e.message}"
      { error: "Unable to retrieve locations. Please try again." }
    end

    private

    def text_search(query)
      normalized_query = query.downcase.strip

      results = @locations.select do |location|
        location[:name].downcase.include?(normalized_query) ||
          location[:address].downcase.include?(normalized_query)
      end

      if results.empty?
        return {
          message: "No locations found matching: '#{query}'",
          total_locations: @locations.length,
          all_locations: @locations.map { |l| l[:name] }
        }
      end

      {
        query: query,
        results_count: results.length,
        locations: results
      }
    end

    def proximity_search(lat, lon)
      # Calculate distance for each location and sort
      locations_with_distance = @locations.map do |location|
        coords = location[:coordinates]
        distance = haversine_distance(lat, lon, coords[:latitude], coords[:longitude])

        location.merge(
          distance_miles: distance.round(2),
          distance_km: (distance * 1.60934).round(2)
        )
      end

      # Sort by distance
      sorted_locations = locations_with_distance.sort_by { |l| l[:distance_miles] }

      {
        search_coordinates: { latitude: lat, longitude: lon },
        nearest_location: sorted_locations.first[:name],
        locations: sorted_locations
      }
    end

    # Haversine formula to calculate distance between two coordinates
    def haversine_distance(lat1, lon1, lat2, lon2)
      earth_radius_miles = 3959.0
      d_lat = to_radians(lat2 - lat1)
      d_lon = to_radians(lon2 - lon1)

      a = Math.sin(d_lat / 2)**2 +
          Math.cos(to_radians(lat1)) * Math.cos(to_radians(lat2)) *
          Math.sin(d_lon / 2)**2

      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      earth_radius_miles * c
    end

    def to_radians(degrees)
      degrees * Math::PI / 180
    end
  end

  class GeneralFaq < RubyLLM::Tool
    description "Searches FAQ database for specific topics or keywords. Categories: allergens, dietary_options, ordering, payment, menu, policies, about"

    param :category, type: :string, required: false,
          desc: "FAQ category (allergens, dietary_options, ordering, payment, menu, policies, about). Returns all categories if not specified."
    param :query, type: :string, required: false,
          desc: "Search query to filter FAQ entries by keyword across all categories"

    def initialize
      @faqs = {
        allergens: {
          peanuts: "We do NOT use peanuts or peanut products in any of our menu items.",
          tree_nuts: "We do not use tree nuts, but our facility is not nut-free certified.",
          gluten: "We offer gluten-free pizza crusts (10-inch only). Prepared in shared kitchen.",
          dairy: "We offer vegan cheese as a dairy-free option.",
          shellfish: "We do not use shellfish. Our anchovies are fish, not shellfish."
        },

        dietary_options: {
          vegetarian: "Yes, we have many vegetarian options including our Margherita, Veggie Supreme, and custom pizzas.",
          vegan: "Yes! We offer vegan cheese and have several vegan-friendly pizzas. Just ask!",
          gluten_free: "Gluten-free crusts available in 10-inch size only. Made in shared kitchen.",
          keto: "We offer a cauliflower crust option for low-carb diets.",
          halal: "Our pepperoni and sausage are not halal certified. Vegetarian options available."
        },

        ordering: {
          delivery_fee: "Delivery fee is $3.99 for orders under $25, free for orders over $25.",
          minimum_order: "Minimum delivery order is $15 before tax.",
          delivery_area: "We deliver within 3 miles of each location.",
          delivery_time: "Average delivery time is 30-45 minutes.",
          online_ordering: "Yes! Order online at www.tonyspizza.com or through our app.",
          phone_orders: "Yes, call either location to place an order.",
          catering: "Yes, we cater events! Call us at least 48 hours in advance."
        },

        payment: {
          accepted_payments: "We accept cash, all major credit cards, debit cards, Apple Pay, and Google Pay.",
          tips: "Tips are appreciated but never required. You can add tips on card payments.",
          gift_cards: "Yes, gift cards available for purchase at both locations or online."
        },

        menu: {
          pizza_sizes: "We offer 10-inch (personal), 14-inch (medium), and 18-inch (large) pizzas.",
          slices: "Yes! We sell pizza by the slice at both locations during lunch hours (11 AM - 3 PM).",
          appetizers: "Yes - garlic knots, mozzarella sticks, wings, salads, and more.",
          desserts: "Cannoli, tiramisu, and gelato available.",
          drinks: "Soft drinks, Italian sodas, beer, and wine available.",
          kids_menu: "Yes, we have a kids menu with smaller portions and kid-friendly options."
        },

        policies: {
          reservations: "Reservations accepted for parties of 6 or more. Call ahead.",
          groups: "Large groups welcome! Call ahead for groups over 8 people.",
          wifi: "Free WiFi available at both locations. Ask staff for password.",
          dogs: "Dogs welcome on our outdoor patio (Brooklyn location only).",
          byob: "No, we have a full beverage menu including beer and wine.",
          loyalty_program: "Yes! Join our rewards program - earn 1 point per dollar spent."
        },

        about: {
          family_owned: "Yes, Tony's Pizza is family-owned and operated since 1985.",
          recipes: "All our recipes are family recipes passed down through generations.",
          ingredients: "We use fresh, locally-sourced ingredients whenever possible.",
          dough: "Our dough is made fresh daily in-house.",
          sauce: "Our signature sauce is made from imported San Marzano tomatoes."
        }
      }
    end

    def execute(category: nil, query: nil)
      # If query is provided, search across all FAQs
      return search_faqs(query) if query.present?

      # If category is provided, return that specific category
      if category.present?
        category_symbol = category.to_s.downcase.to_sym

        unless @faqs.key?(category_symbol)
          return {
            error: "Unknown category: '#{category}'",
            available_categories: @faqs.keys.map(&:to_s)
          }
        end

        return {
          category: category_symbol.to_s,
          faqs: @faqs[category_symbol]
        }
      end

      # No parameters - return category list for discovery
      {
        message: "Available FAQ categories. Use 'category' parameter to get specific FAQs or 'query' to search.",
        available_categories: @faqs.keys.map(&:to_s),
        total_categories: @faqs.keys.length
      }
    end

    private

    def search_faqs(query)
      return { error: "Query too short. Please provide at least 2 characters." } if query.length < 2

      normalized_query = query.downcase.strip
      results = {}

      @faqs.each do |category, items|
        matches = items.select do |key, value|
          key_match = key.to_s.gsub("_", " ").downcase.include?(normalized_query)
          value_match = value.downcase.include?(normalized_query)
          key_match || value_match
        end

        results[category] = matches unless matches.empty?
      end

      if results.empty?
        return {
          message: "No results found for: '#{query}'",
          suggestion: "Try a different search term or browse categories",
          available_categories: @faqs.keys.map(&:to_s)
        }
      end

      {
        query: query,
        results_count: results.sum { |_, items| items.count },
        results: results
      }
    end
  end
end
