# frozen_string_literal: true

module Tools
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
