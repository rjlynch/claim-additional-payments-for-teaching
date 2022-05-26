# This class is a retrofit to allow a combined journey/flow to cater for more than one type of claim.
#
# Doing so without changing every form in the views and helpers from acting on a single model approach.
#
# All references to `current_claim` used to be on a Claim model, this acts as a wrapper to delegate
# to multiple claims for different policies if a `Journey` specifies multiple policies.
#
# Existing single policy journeys will work as they were (StudentLoans, MathsAndPhysics).
#
# ECP will no longer be a single policy journey. This is being upgraded to handle ECP and LUP in a single journey.
#
# The new ECP & LUP journey will have 2 claims being updated until a claim type is selected and one of these
# claims are submitted, from then on that is the claim to be acted upon after submission.

class CurrentClaim
  attr_reader :claims

  def initialize(claims:)
    @claims = claims
  end

  def for_policy(policy)
    claims.find { |c| c.eligibility_type == "#{policy}::Eligibility" }
  end

  # This might need to change default to ECP for now
  def main_claim
    for_policy(EarlyCareerPayments) || claims.first
  end

  # method_missing does not catch this
  def to_param
    main_claim.to_param
  end

  def claim_ids
    claims.map(&:id)
  end

  def reset_eligibility_dependent_answers
    claims.each do |c|
      c.eligibility.reset_dependent_answers
    end
  end

  def method_missing(method_name, *args, &block)
    if [:attributes=, :save, :save!, :update, :update!, :reset_dependent_answers].include?(method_name)
      claims.each do |c|
        c.send(method_name, *args, &block) unless c == main_claim
      end
    end

    main_claim.send(method_name, *args, &block)
  end

  def respond_to_missing?(method_name, *args)
    main_claim.respond_to?(method_name, *args)
  end
end