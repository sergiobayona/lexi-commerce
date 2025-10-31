# RubyLLM Tools Quick Reference

## Tool Overview

Three specialized tools for handling customer inquiries about Tony's Pizza:

| Tool | Purpose | Parameters | Use Cases |
|------|---------|------------|-----------|
| **BusinessHours** | Store hours & open/closed status | `day` (optional) | "Are you open?", "Hours for Friday?" |
| **Locations** | Store locations & proximity search | `search`, `latitude`, `longitude` | "Where are you?", "Nearest location?" |
| **GeneralFaq** | FAQ search & policies | `category`, `query` | "Vegan options?", "Delivery fee?" |

---

## BusinessHours Tool

### Description
Gets business hours for Tony's Pizza with real-time open/closed status.

### Parameters
```ruby
day: string, optional
# Values: "monday" through "sunday", or "today"
# Default: Returns all days
```

### Examples

**Get all hours:**
```ruby
Tools::BusinessHours.new.execute
# Returns: All days with current day/time and status
```

**Check specific day:**
```ruby
Tools::BusinessHours.new.execute(day: "friday")
# Returns: { day: "friday", hours: "11:00 AM - 11:00 PM", current_status: "closed" }
```

**Check today:**
```ruby
Tools::BusinessHours.new.execute(day: "today")
# Returns: Today's hours with is_today: true and current open/closed status
```

### Response Fields
- `business_name` - Business name
- `location` - Primary location address
- `phone` - Contact phone
- `day` - Requested day (if specific day requested)
- `hours` - Hours for that day (e.g., "11:00 AM - 10:00 PM")
- `is_today` - Boolean indicating if it's today
- `current_status` - "open", "closed", or "unknown"
- `special_notes` - Holiday closures, etc.

### Error Handling
```ruby
# Invalid day
Tools::BusinessHours.new.execute(day: "notaday")
# Returns: { error: "Invalid day: 'notaday'. Please use monday-sunday or 'today'." }
```

---

## Locations Tool

### Description
Search for locations by name/city or find nearest location by coordinates.

### Parameters
```ruby
search: string, optional
# Text search in location name or address

latitude: number, optional
# Latitude for proximity search (-90 to 90)

longitude: number, optional
# Longitude for proximity search (-180 to 180)
# Note: Both lat/lon required for proximity search
```

### Examples

**Get all locations:**
```ruby
Tools::Locations.new.execute
# Returns: All 2 locations with full details
```

**Search by city:**
```ruby
Tools::Locations.new.execute(search: "Brooklyn")
# Returns: { results_count: 1, locations: [...] }
```

**Find nearest location:**
```ruby
# Times Square coordinates
Tools::Locations.new.execute(latitude: 40.758, longitude: -73.985)
# Returns: Sorted by distance with nearest_location field
```

### Response Fields

**Standard response:**
- `total_locations` - Total number of locations
- `locations` - Array of location objects

**Search response:**
- `query` - Search term
- `results_count` - Number of matches
- `locations` - Matching locations

**Proximity response:**
- `search_coordinates` - Input coordinates
- `nearest_location` - Name of closest location
- `locations` - All locations sorted by distance
  - Each includes `distance_miles` and `distance_km`

### Location Object Structure
```ruby
{
  name: "Tony's Pizza - Brooklyn",
  address: "123 Main Street, Brooklyn, NY 11201",
  phone: "(555) 123-4567",
  email: "brooklyn@tonyspizza.com",
  features: ["Dine-in", "Takeout", "Delivery", ...],
  parking: "Street parking available",
  accessibility: "Wheelchair accessible",
  coordinates: { latitude: 40.6782, longitude: -73.9442 },
  distance_miles: 2.5,  # Only in proximity search
  distance_km: 4.0      # Only in proximity search
}
```

### Error Handling
```ruby
# Missing coordinate
Tools::Locations.new.execute(latitude: 40.7)
# Returns: { error: "Both latitude and longitude are required for proximity search" }

# Invalid coordinate
Tools::Locations.new.execute(latitude: 100, longitude: -74)
# Returns: { error: "Latitude must be between -90 and 90" }

# No results
Tools::Locations.new.execute(search: "Chicago")
# Returns: { message: "No locations found...", all_locations: [...] }
```

---

## GeneralFaq Tool

### Description
Search FAQ database by category or keyword across all categories.

### Parameters
```ruby
category: string, optional
# Values: "allergens", "dietary_options", "ordering", "payment",
#         "menu", "policies", "about"

query: string, optional
# Keyword search across all FAQs (min 2 characters)
```

### Examples

**List categories:**
```ruby
Tools::GeneralFaq.new.execute
# Returns: { available_categories: [...], total_categories: 7 }
```

**Get category FAQs:**
```ruby
Tools::GeneralFaq.new.execute(category: "dietary_options")
# Returns: { category: "dietary_options", faqs: {...} }
```

**Search by keyword:**
```ruby
Tools::GeneralFaq.new.execute(query: "vegan")
# Returns: { query: "vegan", results_count: 3, results: {...} }
```

### Categories & Content

**allergens**: `peanuts`, `tree_nuts`, `gluten`, `dairy`, `shellfish`

**dietary_options**: `vegetarian`, `vegan`, `gluten_free`, `keto`, `halal`

**ordering**: `delivery_fee`, `minimum_order`, `delivery_area`, `delivery_time`, `online_ordering`, `phone_orders`, `catering`

**payment**: `accepted_payments`, `tips`, `gift_cards`

**menu**: `pizza_sizes`, `slices`, `appetizers`, `desserts`, `drinks`, `kids_menu`

**policies**: `reservations`, `groups`, `wifi`, `dogs`, `byob`, `loyalty_program`

**about**: `family_owned`, `recipes`, `ingredients`, `dough`, `sauce`

### Response Fields

**Category discovery:**
```ruby
{
  message: "Available FAQ categories. Use 'category' parameter...",
  available_categories: ["allergens", "dietary_options", ...],
  total_categories: 7
}
```

**Category results:**
```ruby
{
  category: "allergens",
  faqs: {
    peanuts: "We do NOT use peanuts...",
    gluten: "We offer gluten-free pizza crusts..."
  }
}
```

**Search results:**
```ruby
{
  query: "vegan",
  results_count: 3,
  results: {
    allergens: { dairy: "We offer vegan cheese..." },
    dietary_options: { vegan: "Yes! We offer vegan cheese..." }
  }
}
```

### Error Handling
```ruby
# Unknown category
Tools::GeneralFaq.new.execute(category: "unknown")
# Returns: { error: "Unknown category: 'unknown'", available_categories: [...] }

# Query too short
Tools::GeneralFaq.new.execute(query: "a")
# Returns: { error: "Query too short. Please provide at least 2 characters." }

# No results
Tools::GeneralFaq.new.execute(query: "xyzabc")
# Returns: { message: "No results found for: 'xyzabc'", suggestion: "...", available_categories: [...] }
```

---

## Using with InfoAgent

### Basic Usage
```ruby
agent = Agents::InfoAgent.new
response = agent.ask("What are your business hours?")
```

### Agent automatically:
1. ✅ Analyzes the question
2. ✅ Selects appropriate tool(s)
3. ✅ Determines optimal parameters
4. ✅ Processes tool results
5. ✅ Formats natural language response

### Example Queries & Tool Usage

| Customer Question | Tool Used | Parameters |
|-------------------|-----------|------------|
| "Are you open today?" | BusinessHours | `day: "today"` |
| "What are your Friday hours?" | BusinessHours | `day: "friday"` |
| "Where is your Brooklyn location?" | Locations | `search: "Brooklyn"` |
| "What's the nearest location to me?" | Locations | `latitude: X, longitude: Y` |
| "Do you have gluten-free options?" | GeneralFaq | `query: "gluten"` |
| "What are your allergen policies?" | GeneralFaq | `category: "allergens"` |
| "How much is delivery?" | GeneralFaq | `category: "ordering"` |
| "Can I pay with Apple Pay?" | GeneralFaq | `query: "apple pay"` |

### Custom Model
```ruby
# Use GPT-4 for more complex queries
agent = Agents::InfoAgent.new(model: "gpt-4")
response = agent.ask(complex_question)
```

### Monitoring Tool Calls
Tool calls are automatically logged:
```
[InfoAgent] Tool invoked: business_hours with params: {:day=>"today"}
[InfoAgent] Tool invoked: locations with params: {:search=>"Brooklyn"}
```

---

## Testing

### Running Tests
```bash
# All tool tests
bundle exec rspec spec/services/tools/general_info_spec.rb

# Specific tool
bundle exec rspec spec/services/tools/general_info_spec.rb -e "BusinessHours"

# Agent tests
bundle exec rspec spec/services/agents/info_agent_spec.rb

# With documentation format
bundle exec rspec --format documentation
```

### Test Coverage
- ✅ 45+ test cases across all tools
- ✅ Parameter validation
- ✅ Edge cases and error handling
- ✅ Agent integration and error recovery

---

## Common Patterns

### Pattern 1: Multiple Tool Calls
Agent may use multiple tools to answer complex questions:

**Question**: "Are you open now? Which location is closest to Times Square?"

**Tools Used**:
1. `BusinessHours.execute(day: "today")` → Check if open
2. `Locations.execute(latitude: 40.758, longitude: -73.985)` → Find nearest

### Pattern 2: Fallback Strategy
If search returns no results, tool provides helpful fallback:

```ruby
# Search returns no matches
{
  message: "No locations found matching: 'Chicago'",
  all_locations: ["Tony's Pizza - Brooklyn", "Tony's Pizza - Manhattan"]
}
```

### Pattern 3: Progressive Disclosure
Tools provide different levels of detail based on parameters:

```ruby
# No params → Overview
GeneralFaq.execute  # Lists categories

# Category → Detailed section
GeneralFaq.execute(category: "menu")  # All menu FAQs

# Query → Targeted results
GeneralFaq.execute(query: "pizza size")  # Just size info
```

---

## Best Practices

### For Tool Development
1. ✅ Always validate parameters before processing
2. ✅ Return Ruby hashes (not JSON strings)
3. ✅ Use `{ error: "message" }` for recoverable errors
4. ✅ Raise exceptions only for unrecoverable errors
5. ✅ Provide clear, descriptive parameter documentation
6. ✅ Include helpful error messages and suggestions

### For Agent Usage
1. ✅ Let the agent choose tools (don't hardcode)
2. ✅ Monitor tool calls in logs for debugging
3. ✅ Handle errors gracefully with fallbacks
4. ✅ Test with real-world query variations
5. ✅ Use appropriate model for query complexity

---

## Troubleshooting

### Tool not being called
- Check tool description clarity
- Verify parameter descriptions
- Review system instructions in agent
- Check logs for tool selection reasoning

### Wrong parameters passed
- Verify parameter types match (string, number, etc.)
- Check parameter descriptions are clear
- Ensure validation logic is correct

### Error responses
- Check parameter validation
- Verify data exists for query
- Review error message clarity
- Check logs for stack traces

### Performance issues
- Use optional parameters to limit data
- Implement caching for frequent queries
- Consider database storage for static data
- Monitor token usage in logs

---

## Additional Resources

- [Full Implementation Details](../TOOLS_IMPROVEMENTS.md)
- [RubyLLM Tools Documentation](https://rubyllm.com/tools/)
- [Test Suite](../spec/services/tools/general_info_spec.rb)
- [Agent Implementation](../app/services/agents/info_agent.rb)
