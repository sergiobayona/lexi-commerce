# frozen_string_literal: true

# RouterDecision represents the result of intent routing for a user message
#
# @attr lane [String] The lane to route to (info, commerce, support)
# @attr intent [String] The specific intent identified within the lane
# @attr confidence [Float] Confidence score for the routing decision (0.0-1.0)
# @attr reasons [Array<String>] List of reasons/signals that led to this decision
RouterDecision = Data.define(:lane, :intent, :confidence, :reasons)
