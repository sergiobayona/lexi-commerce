# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::BusinessHours do
  subject(:tool) { described_class.new }

  describe "#execute" do
    context "without parameters" do
      it "returns all business hours" do
        result = tool.execute

        expect(result).to include(:business_name, :location, :phone, :hours, :special_notes)
        expect(result[:business_name]).to eq("Tony's Pizza")
        expect(result[:hours]).to be_a(Hash)
        expect(result[:hours].keys).to match_array(%i[monday tuesday wednesday thursday friday saturday sunday])
      end

      it "includes current day and time" do
        result = tool.execute

        expect(result[:current_day]).to eq(Time.now.strftime("%A").downcase)
        expect(result[:current_time]).to match(/\d{2}:\d{2} (AM|PM)/)
      end

      it "includes current open/closed status" do
        result = tool.execute

        expect(result[:current_status]).to be_in(%w[open closed unknown])
      end
    end

    context "with specific day parameter" do
      it "returns hours for Monday" do
        result = tool.execute(day: "monday")

        expect(result[:day]).to eq("monday")
        expect(result[:hours]).to eq("11:00 AM - 10:00 PM")
      end

      it "returns hours for Friday" do
        result = tool.execute(day: "friday")

        expect(result[:day]).to eq("friday")
        expect(result[:hours]).to eq("11:00 AM - 11:00 PM")
      end

      it "returns hours for Sunday" do
        result = tool.execute(day: "sunday")

        expect(result[:day]).to eq("sunday")
        expect(result[:hours]).to eq("12:00 PM - 9:00 PM")
      end

      it "handles 'today' parameter" do
        result = tool.execute(day: "today")

        expect(result[:day]).to eq(Time.now.strftime("%A").downcase)
        expect(result[:is_today]).to be true
      end

      it "handles mixed case input" do
        result = tool.execute(day: "MoNdAy")

        expect(result[:day]).to eq("monday")
        expect(result[:hours]).to eq("11:00 AM - 10:00 PM")
      end
    end

    context "with invalid day parameter" do
      it "returns error for invalid day name" do
        result = tool.execute(day: "notaday")

        expect(result).to include(:error)
        expect(result[:error]).to include("Invalid day")
      end

      it "returns error for empty string" do
        result = tool.execute(day: "")

        expect(result).to include(:error)
      end
    end

    context "current_status logic" do
      it "includes is_today flag" do
        today = Time.now.strftime("%A").downcase
        result = tool.execute(day: today)

        expect(result[:is_today]).to be true
      end

      it "sets is_today to false for other days" do
        tomorrow = (Time.now + 1.day).strftime("%A").downcase
        result = tool.execute(day: tomorrow)

        expect(result[:is_today]).to be false
      end
    end
  end
end

RSpec.describe Tools::Locations do
  subject(:tool) { described_class.new }

  describe "#execute" do
    context "without parameters" do
      it "returns all locations" do
        result = tool.execute

        expect(result[:total_locations]).to eq(2)
        expect(result[:locations]).to be_an(Array)
        expect(result[:locations].length).to eq(2)
      end

      it "includes location details" do
        result = tool.execute
        location = result[:locations].first

        expect(location).to include(:name, :address, :phone, :email, :features, :coordinates)
      end
    end

    context "with search parameter" do
      it "finds Brooklyn location" do
        result = tool.execute(search: "Brooklyn")

        expect(result[:results_count]).to eq(1)
        expect(result[:locations].first[:name]).to include("Brooklyn")
      end

      it "finds Manhattan location" do
        result = tool.execute(search: "Manhattan")

        expect(result[:results_count]).to eq(1)
        expect(result[:locations].first[:name]).to include("Manhattan")
      end

      it "handles case-insensitive search" do
        result = tool.execute(search: "brooklyn")

        expect(result[:results_count]).to eq(1)
      end

      it "searches in address field" do
        result = tool.execute(search: "Broadway")

        expect(result[:results_count]).to eq(1)
        expect(result[:locations].first[:address]).to include("Broadway")
      end

      it "returns message when no results found" do
        result = tool.execute(search: "Chicago")

        expect(result[:message]).to include("No locations found")
        expect(result[:all_locations]).to be_an(Array)
      end
    end

    context "with coordinate parameters" do
      it "calculates distances for proximity search" do
        # Coordinates near Brooklyn
        result = tool.execute(latitude: 40.68, longitude: -73.94)

        expect(result[:nearest_location]).to include("Brooklyn")
        expect(result[:locations]).to be_an(Array)
        expect(result[:locations].first).to include(:distance_miles, :distance_km)
      end

      it "sorts locations by distance" do
        # Coordinates near Manhattan
        result = tool.execute(latitude: 40.76, longitude: -73.99)

        expect(result[:nearest_location]).to include("Manhattan")
        distances = result[:locations].map { |l| l[:distance_miles] }
        expect(distances).to eq(distances.sort)
      end

      it "includes search coordinates in response" do
        result = tool.execute(latitude: 40.7, longitude: -74.0)

        expect(result[:search_coordinates][:latitude]).to eq(40.7)
        expect(result[:search_coordinates][:longitude]).to eq(-74.0)
      end
    end

    context "parameter validation" do
      it "returns error when only latitude provided" do
        result = tool.execute(latitude: 40.7)

        expect(result[:error]).to include("Both latitude and longitude are required")
      end

      it "returns error when only longitude provided" do
        result = tool.execute(longitude: -74.0)

        expect(result[:error]).to include("Both latitude and longitude are required")
      end

      it "validates latitude range" do
        result = tool.execute(latitude: 100, longitude: -74.0)

        expect(result[:error]).to include("Latitude must be between -90 and 90")
      end

      it "validates longitude range" do
        result = tool.execute(latitude: 40.7, longitude: -200)

        expect(result[:error]).to include("Longitude must be between -180 and 180")
      end
    end
  end
end

RSpec.describe Tools::GeneralFaq do
  subject(:tool) { described_class.new }

  describe "#execute" do
    context "without parameters" do
      it "returns available categories" do
        result = tool.execute

        expect(result[:available_categories]).to be_an(Array)
        expect(result[:total_categories]).to eq(7)
        expect(result[:available_categories]).to include("allergens", "dietary_options", "ordering", "payment", "menu", "policies", "about")
      end
    end

    context "with category parameter" do
      it "returns allergen information" do
        result = tool.execute(category: "allergens")

        expect(result[:category]).to eq("allergens")
        expect(result[:faqs]).to be_a(Hash)
        expect(result[:faqs]).to include(:peanuts, :tree_nuts, :gluten, :dairy)
      end

      it "returns dietary options" do
        result = tool.execute(category: "dietary_options")

        expect(result[:category]).to eq("dietary_options")
        expect(result[:faqs]).to include(:vegetarian, :vegan, :gluten_free, :keto, :halal)
      end

      it "returns ordering information" do
        result = tool.execute(category: "ordering")

        expect(result[:category]).to eq("ordering")
        expect(result[:faqs]).to include(:delivery_fee, :minimum_order, :delivery_area)
      end

      it "handles mixed case category names" do
        result = tool.execute(category: "ALLERGENS")

        expect(result[:category]).to eq("allergens")
      end

      it "returns error for unknown category" do
        result = tool.execute(category: "unknown_category")

        expect(result[:error]).to include("Unknown category")
        expect(result[:available_categories]).to be_an(Array)
      end
    end

    context "with query parameter" do
      it "searches across all categories" do
        result = tool.execute(query: "vegan")

        expect(result[:results_count]).to be > 0
        expect(result[:results]).to be_a(Hash)
      end

      it "finds gluten-free information" do
        result = tool.execute(query: "gluten")

        expect(result[:results_count]).to be > 0
        expect(result[:results]).to include(:allergens, :dietary_options)
      end

      it "searches in both keys and values" do
        result = tool.execute(query: "delivery")

        expect(result[:results_count]).to be > 0
        expect(result[:results][:ordering]).to be_a(Hash)
      end

      it "handles case-insensitive search" do
        result = tool.execute(query: "VEGAN")

        expect(result[:results_count]).to be > 0
      end

      it "returns message when no results found" do
        result = tool.execute(query: "xyzabc123")

        expect(result[:message]).to include("No results found")
        expect(result[:available_categories]).to be_an(Array)
      end

      it "returns error for query that is too short" do
        result = tool.execute(query: "a")

        expect(result[:error]).to include("Query too short")
      end

      it "handles underscore-separated keywords" do
        result = tool.execute(query: "gift card")

        expect(result[:results_count]).to be > 0
        expect(result[:results][:payment]).to include(:gift_cards)
      end
    end
  end
end
