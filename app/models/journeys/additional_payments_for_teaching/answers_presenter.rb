module Journeys
  module AdditionalPaymentsForTeaching
    class AnswersPresenter < BaseAnswersPresenter
      include ActionView::Helpers::TranslationHelper
      include AdditionalPaymentsHelper
      include Claims::IttSubjectHelper

      # Formats the eligibility as a list of questions and answers, each
      # accompanied by a slug for changing the answer. Suitable for playback to
      # the claimant for them to review on the check-your-answers page.
      #
      # Returns an array. Each element of this an array is an array of three
      # elements:
      # [0]: question text;
      # [1]: answer text;
      # [2]: slug for changing the answer.
      def eligibility_answers
        [].tap do |a|
          a << current_school
          a << nqt_in_academic_year_after_itt
          a << induction_completed
          a << employed_as_supply_teacher
          a << has_entire_term_contract if eligibility.employed_as_supply_teacher?
          a << employed_directly if eligibility.employed_as_supply_teacher?
          a << subject_to_formal_performance_action
          a << subject_to_disciplinary_action

          a << qualification
          a << itt_academic_year
          a << eligible_itt_subject
          a << eligible_degree_subject

          a << teaching_subject_now
        end.compact
      end

      def identity_answers
        super.tap do |a|
          a << [translate("questions.provide_mobile_number"), (claim.provide_mobile_number ? "Yes" : "No"), "provide-mobile-number"]
          a << [translate("questions.mobile_number"), claim.mobile_number, "mobile-number"] if claim.provide_mobile_number?
        end
      end

      private

      def has_entire_term_contract
        [
          translate("additional_payments.questions.has_entire_term_contract"),
          (eligibility.has_entire_term_contract? ? "Yes" : "No"),
          "entire-term-contract"
        ]
      end

      def current_school
        [
          translate("additional_payments.forms.current_school.questions.current_school_search"),
          eligibility.current_school_name,
          (eligibility.school_somewhere_else == false) ? "correct-school" : "current-school"
        ]
      end

      def nqt_in_academic_year_after_itt
        [
          translate("additional_payments.questions.nqt_in_academic_year_after_itt.heading"),
          (eligibility.nqt_in_academic_year_after_itt? ? "Yes" : "No"),
          "nqt-in-academic-year-after-itt"
        ]
      end

      def induction_completed
        [
          translate("additional_payments.questions.induction_completed.heading"),
          (eligibility.induction_completed? ? "Yes" : "No"),
          "induction-completed"
        ]
      end

      def employed_as_supply_teacher
        [
          translate("additional_payments.questions.employed_as_supply_teacher"),
          (eligibility.employed_as_supply_teacher? ? "Yes" : "No"),
          "supply-teacher"
        ]
      end

      def employed_directly
        [
          translate("additional_payments.questions.employed_directly"),
          (eligibility.employed_directly? ? "Yes" : "No"),
          "employed-directly"
        ]
      end

      def subject_to_formal_performance_action
        [
          translate("additional_payments.questions.formal_performance_action"),
          (eligibility.subject_to_formal_performance_action? ? "Yes" : "No"),
          "poor-performance"
        ]
      end

      def subject_to_disciplinary_action
        [
          translate("additional_payments.questions.disciplinary_action"),
          (eligibility.subject_to_disciplinary_action? ? "Yes" : "No"),
          "poor-performance"
        ]
      end

      def qualification
        return if eligibility.claim.qualifications_details_check && eligibility.claim.dqt_teacher_record&.route_into_teaching

        [
          translate("additional_payments.questions.qualification.heading"),
          translate("early_career_payments.answers.qualification.#{eligibility.qualification}"),
          "qualification"
        ]
      end

      def eligible_itt_subject
        return if eligibility.claim.qualifications_details_check && eligibility.claim.dqt_teacher_record&.eligible_itt_subject_for_claim

        [
          eligible_itt_subject_translation(CurrentClaim.new(claims: [eligibility.claim])),
          text_for_subject_answer,
          "eligible-itt-subject"
        ]
      end

      def eligible_degree_subject
        return if !eligibility.respond_to?(:eligible_degree_subject) || !eligibility.eligible_degree_subject? || (eligibility.claim.qualifications_details_check && eligibility.claim.dqt_teacher_record&.eligible_degree_code?)

        [
          translate("additional_payments.questions.eligible_degree_subject"),
          "Yes",
          "eligible-degree-subject"
        ]
      end

      def teaching_subject_now
        [
          translate("additional_payments.questions.teaching_subject_now", eligible_itt_subject: eligibility.eligible_itt_subject),
          (eligibility.teaching_subject_now? ? "Yes" : "No"),
          "teaching-subject-now"
        ]
      end

      def itt_academic_year
        return if eligibility.claim.qualifications_details_check && eligibility.claim.dqt_teacher_record&.itt_academic_year_for_claim

        [
          I18n.t("additional_payments.questions.itt_academic_year.qualification.#{eligibility.qualification}"),
          eligibility.itt_academic_year.to_s.gsub("/", " - "),
          "itt-year"
        ]
      end

      def text_for_subject_answer
        policy = eligibility.policy
        subjects = JourneySubjectEligibilityChecker.new(claim_year: Journeys.for_policy(policy).configuration.current_academic_year,
          itt_year: eligibility.itt_academic_year).current_and_future_subject_symbols(policy)

        if subjects.many?
          translate("early_career_payments.answers.eligible_itt_subject.#{eligibility.eligible_itt_subject}")
        else
          subject_symbol = subjects.first
          (subject_symbol == eligibility.eligible_itt_subject.to_sym) ? "Yes" : "No"
        end
      end
    end
  end
end
