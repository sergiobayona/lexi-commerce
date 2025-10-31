# frozen_string_literal: true

module Tools
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
end
