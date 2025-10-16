module Tools
  # GeneralInfoTools provides tools for fetching general information like weather
  class GeneralInfo
    def self.all
      [ BusinessHours, Locations, GeneralFaq ]
    end
  end

  class BusinessHours < RubyLLM::Tool
    description "Gets the business hours for Tony's Pizza"

    def initialize
      @business_name = "Tony's Pizza"
      @location = "123 Main Street, Brooklyn, NY"
      @phone = "(555) 123-4567"

      # Hard-coded business hours
      @hours = {
        monday: "11:00 AM - 10:00 PM",
        tuesday: "11:00 AM - 10:00 PM",
        wednesday: "11:00 AM - 10:00 PM",
        thursday: "11:00 AM - 10:00 PM",
        friday: "11:00 AM - 11:00 PM",
        saturday: "11:00 AM - 11:00 PM",
        sunday: "12:00 PM - 9:00 PM"
      }

      @special_notes = "Closed on Thanksgiving and Christmas Day"
    end

    def execute
      {
        business_name: @business_name,
        location: @location,
        phone: @phone,
        hours: @hours,
        special_notes: @special_notes,
        current_day: Time.now.strftime("%A").downcase,
        current_time: Time.now.strftime("%I:%M %p")
      }.to_json
    end
  end

  class Locations < RubyLLM::Tool
    description "Gets location information for Tony's Pizza locations, including addresses, contact info, and features"

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

    def execute
      {
        total_locations: @locations.length,
        locations: @locations
      }.to_json
    end
  end

  class GeneralFaq < RubyLLM::Tool
    description "Answers frequently asked questions about Tony's Pizza policies, ingredients, dietary options, and general information"

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

    def execute
      @faqs.to_json
    end
  end
end
