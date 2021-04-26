module EarlyCareerPayments
  class EligibilityAnswersPresenter
    include ActionView::Helpers::TranslationHelper

    attr_reader :eligibility

    def initialize(eligibility)
      @eligibility = eligibility
    end

    # Formats the eligibility as a list of questions and answers, each
    # accompanied by a slug for changing the answer. Suitable for playback to
    # the claimant for them to review on the check-your-answers page.
    #
    # Returns an array. Each element of this an array is an array of three
    # elements:
    # [0]: question text;
    # [1]: answer text;
    # [2]: slug for changing the answer.
    def answers
      [].tap do |a|
        a << nqt_in_academic_year_after_itt
        a << employed_as_supply_teacher
        a << has_entire_term_contract if eligibility.employed_as_supply_teacher?
        a << employed_directly if eligibility.employed_as_supply_teacher?
        a << subject_to_disciplinary_action
      end
    end

    private

    def has_entire_term_contract
      [
        translate("early_career_payments.questions.has_entire_term_contract"),
        (eligibility.has_entire_term_contract? ? "Yes" : "No"),
        "entire-term-contract"
      ]
    end

    def nqt_in_academic_year_after_itt
      [
        translate("early_career_payments.questions.nqt_in_academic_year_after_itt"),
        (eligibility.nqt_in_academic_year_after_itt? ? "Yes" : "No"),
        "nqt-in-academic-year-after-itt"
      ]
    end

    def employed_as_supply_teacher
      [
        translate("early_career_payments.questions.employed_as_supply_teacher"),
        (eligibility.employed_as_supply_teacher? ? "Yes" : "No"),
        "supply-teacher"
      ]
    end

    def employed_directly
      [
        translate("early_career_payments.questions.employed_directly"),
        (eligibility.employed_directly? ? "Yes" : "No"),
        "employed-directly"
      ]
    end

    def subject_to_disciplinary_action
      [
        translate("early_career_payments.questions.disciplinary_action"),
        (eligibility.subject_to_disciplinary_action? ? "Yes" : "No"),
        "disciplinary-action"
      ]
    end
  end
end