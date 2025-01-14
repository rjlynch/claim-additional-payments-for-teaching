# frozen_string_literal: true

class Claim < ApplicationRecord
  include ::OneTimePasswordCheckable

  MIN_QA_THRESHOLD = 10
  TRN_LENGTH = 7
  NO_STUDENT_LOAN = "not_applicable"
  STUDENT_LOAN_PLAN_OPTIONS = StudentLoan::PLANS.dup << NO_STUDENT_LOAN
  ADDRESS_ATTRIBUTES = %w[address_line_1 address_line_2 address_line_3 address_line_4 postcode].freeze
  EDITABLE_ATTRIBUTES = [
    :first_name,
    :middle_name,
    :surname,
    :address_line_1,
    :address_line_2,
    :address_line_3,
    :address_line_4,
    :postcode,
    :date_of_birth,
    :payroll_gender,
    :teacher_reference_number,
    :national_insurance_number,
    :email_address,
    :provide_mobile_number,
    :mobile_number,
    :bank_or_building_society,
    :bank_sort_code,
    :bank_account_number,
    :banking_name,
    :building_society_roll_number,
    :one_time_password,
    :logged_in_with_tid,
    :details_check,
    :email_address_check,
    :mobile_check,
    :qualifications_details_check
  ].freeze
  AMENDABLE_ATTRIBUTES = %i[
    teacher_reference_number
    national_insurance_number
    date_of_birth
    student_loan_plan
    bank_sort_code
    bank_account_number
    building_society_roll_number
  ].freeze
  FILTER_PARAMS = {
    address_line_1: true,
    address_line_2: true,
    address_line_3: true,
    address_line_4: true,
    postcode: true,
    payroll_gender: true,
    teacher_reference_number: true,
    national_insurance_number: true,
    has_student_loan: false,
    student_loan_country: false,
    student_loan_courses: false,
    student_loan_start_date: false,
    has_masters_doctoral_loan: false,
    postgraduate_masters_loan: false,
    postgraduate_doctoral_loan: false,
    email_address: true,
    provide_mobile_number: false,
    mobile_number: true,
    bank_sort_code: true,
    bank_account_number: true,
    created_at: false,
    date_of_birth: true,
    date_of_birth_day: true,
    date_of_birth_month: true,
    date_of_birth_year: true,
    eligibility_id: false,
    eligibility_type: false,
    first_name: true,
    middle_name: true,
    surname: true,
    id: false,
    reference: false,
    student_loan_plan: false,
    submitted_at: false,
    updated_at: false,
    govuk_verify_fields: false,
    bank_or_building_society: false,
    banking_name: true,
    building_society_roll_number: true,
    academic_year: false,
    personal_data_removed_at: false,
    email_verified: false,
    one_time_password: true,
    sent_one_time_password_at: false,
    mobile_verified: false,
    one_time_password_category: false,
    assigned_to_id: true,
    policy_options_provided: false,
    held: false,
    hmrc_bank_validation_responses: false,
    hmrc_bank_validation_succeeded: false,
    logged_in_with_tid: false,
    teacher_id_user_info: false,
    details_check: true,
    email_address_check: true,
    mobile_check: true,
    qa_required: false,
    qa_completed_at: false,
    qualifications_details_check: true,
    dqt_teacher_status: false,
    submitted_using_slc_data: false
  }.freeze
  DECISION_DEADLINE = 12.weeks
  DECISION_DEADLINE_WARNING_POINT = 2.weeks
  ATTRIBUTE_DEPENDENCIES = {
    "national_insurance_number" => ["has_student_loan", "student_loan_plan", "eligibility.student_loan_repayment_amount"],
    "date_of_birth" => ["has_student_loan", "student_loan_plan", "eligibility.student_loan_repayment_amount"],
    "bank_or_building_society" => ["banking_name", "bank_account_number", "bank_sort_code", "building_society_roll_number"],
    "provide_mobile_number" => ["mobile_number"],
    "mobile_number" => ["mobile_verified"],
    "email_address" => ["email_verified"]
  }.freeze

  # The idea is to filter things that in a CSV export might be malicious in MS Excel
  # A whitelist would be inappropiate as these fields could contain valid special letters e.g. accents and umlauts
  NAME_REGEX_FILTER = /\A[^"=$%#&*+\/\\()@?!<>0-9]*\z/
  ADDRESS_REGEX_FILTER = /\A[^'"=$%#*+\/\\()@?!<>]*\z/

  # Use AcademicYear as custom ActiveRecord attribute type
  attribute :academic_year, AcademicYear::Type.new

  attribute :date_of_birth_day, :integer
  attribute :date_of_birth_month, :integer
  attribute :date_of_birth_year, :integer

  enum student_loan_country: StudentLoan::COUNTRIES
  enum student_loan_start_date: StudentLoan::COURSE_START_DATES
  enum student_loan_courses: {one_course: 0, two_or_more_courses: 1}
  enum bank_or_building_society: {personal_bank_account: 0, building_society: 1}

  has_many :decisions, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :amendments, dependent: :destroy
  has_many :topups, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_one :support_ticket, dependent: :destroy

  belongs_to :eligibility, polymorphic: true, inverse_of: :claim, dependent: :destroy
  accepts_nested_attributes_for :eligibility, update_only: true
  delegate :eligible_itt_subject, to: :eligibility, allow_nil: true

  has_many :claim_payments, dependent: :destroy
  has_many :payments, through: :claim_payments

  belongs_to :assigned_to, class_name: "DfeSignIn::User",
    inverse_of: :assigned_claims,
    optional: true

  enum payroll_gender: {
    dont_know: 0,
    female: 1,
    male: 2
  }

  validates :academic_year_before_type_cast, format: {with: AcademicYear::ACADEMIC_YEAR_REGEXP}

  validates :payroll_gender, on: [:gender, :submit], presence: {message: "Select the gender recorded on your school’s payroll system or select whether you do not know"}

  validates :first_name, on: [:"personal-details-name", :"personal-details", :submit], presence: {message: "Enter your first name"}
  validates :first_name,
    on: [:"personal-details-name", :"personal-details", :submit],
    length: {
      in: 1..100,
      message: "First name must be between 2 and 30 characters"
    },
    format: {
      with: NAME_REGEX_FILTER,
      message: "First name cannot contain special characters"
    },
    if: -> { first_name.present? }

  validates :middle_name,
    on: [:"personal-details", :submit],
    length: {
      maximum: 61,
      message: "Middle names must be less than 61 characters"
    },
    format: {
      with: NAME_REGEX_FILTER,
      message: "Middle names cannot contain special characters"
    },
    if: -> { middle_name.present? }

  validates :surname, on: [:"personal-details-name", :"personal-details", :submit], presence: {message: "Enter your last name"}
  validates :surname,
    on: [:"personal-details-name", :"personal-details", :submit],
    length: {
      in: 1..100,
      message: "Last name must be between 2 and 30 characters"
    },
    format: {
      with: NAME_REGEX_FILTER,
      message: "Last name cannot contain special characters"
    },
    if: -> { surname.present? }

  validates :details_check, on: [:"teacher-detail"], inclusion: {in: [true, false], message: "Select an option to whether the details are correct or not"}
  validates :qualifications_details_check, on: [:"qualification-details"], inclusion: {in: [true, false], message: "Select yes if your qualification details are correct"}
  validates :email_address_check, on: [:"select-email"], inclusion: {in: [true, false], message: "Select an option to indicate whether the email is correct or not"}
  validates :mobile_check, on: [:"select-mobile"], inclusion: {in: ["use", "alternative", "declined"], message: "Select an option to indicate whether the mobile number is correct or not"}
  validates :address_line_1, on: [:address], presence: {message: "Enter a house number or name"}, if: :has_ecp_or_lupp_policy?
  validates :address_line_1, on: [:address, :submit], presence: {message: "Enter a building and street address"}, unless: :has_ecp_or_lupp_policy?
  validates :address_line_1, length: {maximum: 100, message: "Address lines must be 100 characters or less"}
  validates :address_line_1, on: [:address], format: {with: ADDRESS_REGEX_FILTER, message: "Address lines cannot contain special characters"}
  validates :address_line_2, length: {maximum: 100, message: "Address lines must be 100 characters or less"}
  validates :address_line_2, on: [:address], presence: {message: "Enter a building and street address"}, if: :has_ecp_or_lupp_policy?
  validates :address_line_2, on: [:address], format: {with: ADDRESS_REGEX_FILTER, message: "Address lines cannot contain special characters"}
  validates :address_line_3, length: {maximum: 100, message: "Address lines must be 100 characters or less"}
  validates :address_line_3, on: [:address], presence: {message: "Enter a town or city"}
  validates :address_line_3, on: [:address], format: {with: ADDRESS_REGEX_FILTER, message: "Address lines cannot contain special characters"}
  validates :address_line_4, length: {maximum: 100, message: "Address lines must be 100 characters or less"}
  validates :address_line_4, on: [:address], presence: {message: "Enter a county"}
  validates :address_line_4, on: [:address], format: {with: ADDRESS_REGEX_FILTER, message: "Address lines cannot contain special characters"}

  validates :postcode, on: [:address, :submit], presence: {message: "Enter a real postcode"}
  validates :postcode, length: {maximum: 11, message: "Postcode must be 11 characters or less"}
  validate :postcode_is_valid, if: -> { postcode.present? }

  validate :date_of_birth_criteria, on: [:"personal-details-dob", :"personal-details", :submit, :amendment]

  validates :teacher_reference_number, on: [:"teacher-reference-number", :submit, :amendment], presence: {message: "Enter your teacher reference number"}
  validate :trn_must_be_seven_digits

  validates :national_insurance_number, on: [:"personal-details-nino", :"personal-details", :submit, :amendment], presence: {message: "Enter a National Insurance number in the correct format"}
  validate :ni_number_is_correct_format

  validates :has_student_loan, on: [:"student-loan"], inclusion: {in: [true, false]}
  validates :student_loan_plan, inclusion: {in: STUDENT_LOAN_PLAN_OPTIONS}, allow_nil: true
  validates :student_loan_plan, on: [:"student-loan", :amendment], presence: {message: "Enter a valid student loan plan"}

  validates :email_address, on: [:"email-address", :submit], presence: {message: "Enter an email address"}
  validates :email_address, format: {with: Rails.application.config.email_regexp, message: "Enter an email address in the correct format, like name@example.com"},
    length: {maximum: 256, message: "Email address must be 256 characters or less"}, if: -> { email_address.present? }

  validates :provide_mobile_number, on: [:"provide-mobile-number", :submit], inclusion: {in: [true, false], message: "Select yes if you would like to provide your mobile number"}, if: :has_ecp_or_lupp_policy?
  validates :mobile_number, on: [:"mobile-number", :submit], presence: {message: "Enter a mobile number, like 07700 900 982 or +44 7700 900 982"}, if: -> { provide_mobile_number == true && has_ecp_or_lupp_policy? }
  validates :mobile_number,
    format: {
      with: /\A(\+44\s?)?(?:\d\s?){10,11}\z/,
      message: "Enter a valid mobile number, like 07700 900 982 or +44 7700 900 982"
    }, if: -> { provide_mobile_number == true && mobile_number.present? }

  validates :bank_or_building_society, on: [:"bank-or-building-society", :submit], presence: {message: "Select if you want the money paid in to a personal bank account or building society"}
  validates :banking_name, on: [:"personal-bank-account", :"building-society-account", :submit, :amendment], presence: {message: "Enter a name on the account"}
  validates :bank_sort_code, on: [:"personal-bank-account", :"building-society-account", :submit, :amendment], presence: {message: "Enter a sort code"}
  validates :bank_account_number, on: [:"personal-bank-account", :"building-society-account", :submit, :amendment], presence: {message: "Enter an account number"}
  validates :building_society_roll_number, on: [:"building-society-account", :submit, :amendment], presence: {message: "Enter a roll number"}, if: -> { building_society? }

  validates :payroll_gender, on: [:"payroll-gender-task", :submit], presence: {message: "You must select a gender that will be passed to HMRC"}

  validate :bank_account_number_must_be_eight_digits
  validate :bank_sort_code_must_be_six_digits
  validate :building_society_roll_number_must_be_between_one_and_eighteen_digits
  validate :building_society_roll_number_must_be_in_a_valid_format

  validate :claim_must_not_be_ineligible, on: :submit

  before_save :normalise_trn, if: :teacher_reference_number_changed?
  before_save :normalise_ni_number, if: :national_insurance_number_changed?
  before_save :normalise_bank_account_number, if: :bank_account_number_changed?
  before_save :normalise_bank_sort_code, if: :bank_sort_code_changed?
  before_save :normalise_first_name, if: :first_name_changed?
  before_save :normalise_surname, if: :surname_changed?

  scope :unsubmitted, -> { where(submitted_at: nil) }
  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :held, -> { where(held: true) }
  scope :not_held, -> { where(held: false) }
  scope :awaiting_decision, -> { submitted.joins("LEFT OUTER JOIN decisions ON decisions.claim_id = claims.id AND decisions.undone = false").where(decisions: {claim_id: nil}) }
  scope :awaiting_task, ->(task_name) { awaiting_decision.joins(sanitize_sql(["LEFT OUTER JOIN tasks ON tasks.claim_id = claims.id AND tasks.name = ?", task_name])).where(tasks: {claim_id: nil}) }
  scope :auto_approved, -> { approved.where(decisions: {created_by: nil}) }
  scope :approved, -> { joins(:decisions).merge(Decision.active.approved) }
  scope :rejected, -> { joins(:decisions).merge(Decision.active.rejected) }
  scope :approaching_decision_deadline, -> { awaiting_decision.where("submitted_at < ? AND submitted_at > ?", DECISION_DEADLINE.ago + DECISION_DEADLINE_WARNING_POINT, DECISION_DEADLINE.ago) }
  scope :passed_decision_deadline, -> { awaiting_decision.where("submitted_at < ?", DECISION_DEADLINE.ago) }
  scope :by_policy, ->(policy) { where(eligibility_type: policy::Eligibility.to_s) }
  scope :by_policies, ->(policies) { where(eligibility_type: policies.map { |p| p::Eligibility.to_s }) }
  scope :by_academic_year, ->(academic_year) { where(academic_year: academic_year) }
  scope :assigned_to_team_member, ->(service_operator_id) { where(assigned_to_id: service_operator_id) }
  scope :by_claims_team_member, ->(service_operator_id, status) do
    if %w[approved approved_awaiting_payroll rejected].include?(status)
      assigned_to_team_member(service_operator_id).or(joins(:decisions).where(decisions: {created_by_id: service_operator_id}))
    else
      assigned_to_team_member(service_operator_id)
    end
  end
  scope :unassigned, -> { where(assigned_to_id: nil) }
  scope :current_academic_year, -> { by_academic_year(AcademicYear.current) }
  scope :failed_bank_validation, -> { where(hmrc_bank_validation_succeeded: false) }

  delegate :award_amount, to: :eligibility

  scope :payrollable, -> { approved.not_awaiting_qa.left_joins(:payments).where(payments: nil).order(submitted_at: :asc) }
  scope :not_awaiting_qa, -> { approved.where("qa_required = false OR (qa_required = true AND qa_completed_at IS NOT NULL)") }
  scope :awaiting_qa, -> { approved.qa_required.where(qa_completed_at: nil) }
  scope :qa_required, -> { where(qa_required: true) }

  # This method's intention is to help make a decision on whether a claim should
  # be flagged for QA or not. These criteria need to be met for each academic year:
  #
  # 1. the first claim to be approved should always be flagged for QA
  # 2. subsequently approved claims should be flagged for QA, 1 in 100/MIN_QA_THRESHOLD.
  #
  # This method should be used every time a new approval decision is being made;
  # when used retrospectively, i.e. when several claims have been approved,
  # the method returns:
  #
  # 1. `true` if none of then claims have been flagged for QA
  # 2. `true` if some claims have been flagged for QA using a lower MIN_QA_THRESHOLD
  # 3. `false` if some claims have been flagged for QA using a higher MIN_QA_THRESHOLD
  #
  # Newly approved claims should not be flagged for QA for as long as the method
  # returns `false`; they should be flagged for QA otherwise.
  def self.below_min_qa_threshold?
    return false if MIN_QA_THRESHOLD.zero?

    claims_approved_so_far = current_academic_year.approved.count
    return true if claims_approved_so_far.zero?

    (current_academic_year.approved.qa_required.count.to_f / claims_approved_so_far) * 100 <= MIN_QA_THRESHOLD
  end

  def submit!
    raise NotSubmittable unless submittable?

    self.submitted_at = Time.zone.now
    self.reference = unique_reference
    eligibility&.submit!
    save!
  end

  def hold!(reason:, user:)
    if holdable? && !held?
      self.class.transaction do
        update!(held: true)
        notes.create!(body: "Claim put on hold: #{reason}", created_by: user)
      end
    end
  end

  def unhold!(user:)
    if held?
      self.class.transaction do
        update!(held: false)
        notes.create!(body: "Claim hold removed", created_by: user)
      end
    end
  end

  def submitted?
    submitted_at.present?
  end

  def submittable?
    valid?(:submit) && !submitted? && submittable_email_details? && submittable_mobile_details?
  end

  def approvable?
    submitted? && !held? && !payroll_gender_missing? && (!decision_made? || awaiting_qa?) && !payment_prevented_by_other_claims?
  end

  def rejectable?
    !held?
  end

  def holdable?
    !decision_made?
  end

  def flaggable_for_qa?
    decision_made? && latest_decision.approved? && Claim.below_min_qa_threshold? && !awaiting_qa? && !qa_completed?
  end

  def qa_completed?
    qa_completed_at?
  end

  def awaiting_qa?
    qa_required? && !qa_completed?
  end

  def latest_decision
    decisions.active.last
  end

  def previous_decision
    decisions.last(2).first
  end

  def decision_made?
    latest_decision.present? && latest_decision.persisted?
  end

  def payroll_gender_missing?
    %w[male female].exclude?(payroll_gender)
  end

  def payment_prevented_by_other_claims?
    ClaimsPreventingPaymentFinder.new(self).claims_preventing_payment.any?
  end

  def decision_deadline_date
    (submitted_at + DECISION_DEADLINE).to_date
  end

  def address(separator = ", ")
    Claim::ADDRESS_ATTRIBUTES.map { |attr| send(attr) }.reject(&:blank?).join(separator)
  end

  # Returns true if the claim has a verified identity received from GOV.UK Verify.
  # TODO: We no longer use GOV.UK Verify these verified? methods aren't used anymore.
  def identity_verified?
    govuk_verify_fields.any?
  end

  def name_verified?
    govuk_verify_fields.include?("first_name")
  end

  def date_of_birth_verified?
    govuk_verify_fields.include?("date_of_birth")
  end

  def payroll_gender_verified?
    govuk_verify_fields.include?("payroll_gender")
  end

  def address_from_govuk_verify?
    (ADDRESS_ATTRIBUTES & govuk_verify_fields).any?
  end

  def personal_data_removed?
    personal_data_removed_at.present?
  end

  def payrolled?
    payments.present?
  end

  def all_payrolled?
    if has_lupp_policy?
      topups.all? { |t| t.payrolled? } && payrolled?
    else
      payrolled?
    end
  end

  def topupable?
    has_lupp_policy? && submitted? && all_payrolled?
  end

  def full_name
    [first_name, middle_name, surname].reject(&:blank?).join(" ")
  end

  def self.filtered_params
    FILTER_PARAMS.select { |_, v| v }.keys
  end

  def reset_dependent_answers
    ATTRIBUTE_DEPENDENCIES.each do |attribute_name, dependent_attribute_names|
      dependent_attribute_names.each do |dependent_attribute_name|
        next unless changed.include?(attribute_name)

        target_model, dependent_attribute_name = dependent_attribute_name.split(".") if dependent_attribute_name.include?(".")
        target_model ||= "itself"

        next unless send(target_model).has_attribute?(dependent_attribute_name)

        send(target_model).write_attribute(dependent_attribute_name, nil)
      end
    end
  end

  def policy
    eligibility&.policy
  end

  def school
    eligibility&.current_school
  end

  def amendable?
    submitted? && !payrolled? && !personal_data_removed?
  end

  def decision_undoable?
    decision_made? && !payrolled? && !personal_data_removed?
  end

  def has_ecp_policy?
    policy == Policies::EarlyCareerPayments
  end

  def has_tslr_policy?
    policy == Policies::StudentLoans
  end

  def has_lupp_policy?
    policy == Policies::LevellingUpPremiumPayments
  end

  def has_ecp_or_lupp_policy?
    has_ecp_policy? || has_lupp_policy?
  end

  def important_notes
    notes&.where(important: true)
  end

  def award_amount_with_topups
    topups.sum(:award_amount) + award_amount
  end

  def must_manually_validate_bank_details?
    !hmrc_bank_validation_succeeded?
  end

  def submitted_without_slc_data?
    submitted_using_slc_data == false
  end

  def has_recent_tps_school?
    TeachersPensionsService.has_recent_tps_school?(self)
  end

  def recent_tps_school
    TeachersPensionsService.recent_tps_school(self)
  end

  def has_tps_school_for_student_loan_in_previous_financial_year?
    TeachersPensionsService.has_tps_school_for_student_loan_in_previous_financial_year?(self)
  end

  def tps_school_for_student_loan_in_previous_financial_year
    TeachersPensionsService.tps_school_for_student_loan_in_previous_financial_year(self)
  end

  # dup - because we don't want to pollute the claim.errors by calling this method
  # Used to not show the personal-details page if everything is all valid
  def has_all_valid_personal_details?
    dup.valid?(:"personal-details") && all_personal_details_same_as_tid?
  end

  # This is used to ensure we still show the forms if the personal-details are valid
  # but are valid because they were susequently provided/changed from what was in TID
  def all_personal_details_same_as_tid?
    name_same_as_tid? && dob_same_as_tid? && nino_same_as_tid?
  end

  def name_same_as_tid?
    teacher_id_user_info["given_name"] == first_name && teacher_id_user_info["family_name"] == surname
  end

  def dob_same_as_tid?
    teacher_id_user_info["birthdate"] == date_of_birth.to_s
  end

  def nino_same_as_tid?
    teacher_id_user_info["ni_number"] == national_insurance_number
  end

  # dup - because we don't want to pollute the claim.errors by calling this method
  # Check errors hash for key because we don't care about the non-context validation errors
  def has_valid_name?
    claim_dup = dup
    claim_dup.valid?(:"personal-details-name")
    !(claim_dup.errors.include?(:first_name) || claim_dup.errors.include?(:surname))
  end

  # dup - because we don't want to pollute the claim.errors by calling this method
  # Check errors hash for key because we don't care about the non-context validation errors
  def has_valid_date_of_birth?
    claim_dup = dup
    claim_dup.valid?(:"personal-details-dob")
    !claim_dup.errors.include?(:date_of_birth)
  end

  # dup - because we don't want to pollute the claim.errors by calling this method
  # Check errors hash for key because we don't care about the non-context validation errors
  def has_valid_nino?
    claim_dup = dup
    claim_dup.valid?(:"personal-details-nino")
    !claim_dup.errors.include?(:national_insurance_number)
  end

  def trn_same_as_tid?
    teacher_id_user_info["trn"] == teacher_reference_number
  end

  def logged_in_with_tid_and_has_recent_tps_school?
    logged_in_with_tid? && teacher_reference_number.present? && has_recent_tps_school?
  end

  def has_dqt_record?
    !dqt_teacher_status.blank?
  end

  def dqt_teacher_record
    policy::DqtRecord.new(Dqt::Teacher.new(dqt_teacher_status), self) if has_dqt_record?
  end

  private

  def normalise_trn
    self.teacher_reference_number = normalised_trn
  end

  def normalised_trn
    teacher_reference_number.gsub(/\D/, "")
  end

  def trn_must_be_seven_digits
    errors.add(:teacher_reference_number, "Teacher reference number must be 7 digits") if teacher_reference_number.present? && normalised_trn.length != TRN_LENGTH
  end

  def normalise_ni_number
    self.national_insurance_number = normalised_ni_number
  end

  def normalised_ni_number
    national_insurance_number.gsub(/\s/, "").upcase
  end

  def normalise_first_name
    first_name.strip!
  end

  def normalise_surname
    surname.strip!
  end

  def ni_number_is_correct_format
    errors.add(:national_insurance_number, "Enter a National Insurance number in the correct format") if national_insurance_number.present? && !normalised_ni_number.match(/\A[A-Z]{2}[0-9]{6}[A-D]{1}\Z/)
  end

  def normalise_bank_account_number
    return if bank_account_number.nil?

    self.bank_account_number = normalised_bank_detail(bank_account_number)
  end

  def normalise_bank_sort_code
    return if bank_sort_code.nil?

    self.bank_sort_code = normalised_bank_detail(bank_sort_code)
  end

  def normalised_bank_detail(bank_detail)
    bank_detail.gsub(/\s|-/, "")
  end

  def building_society_roll_number_must_be_between_one_and_eighteen_digits
    return unless building_society_roll_number.present?

    errors.add(:building_society_roll_number, "Building society roll number must be between 1 and 18 characters") if building_society_roll_number.length > 18
  end

  def building_society_roll_number_must_be_in_a_valid_format
    return unless building_society_roll_number.present?

    errors.add(:building_society_roll_number, "Building society roll number must only include letters a to z, numbers, hyphens, spaces, forward slashes and full stops") unless /\A[a-z0-9\-\s.\/]{1,18}\z/i.match?(building_society_roll_number)
  end

  def bank_account_number_must_be_eight_digits
    errors.add(:bank_account_number, "Account number must be 8 digits") if bank_account_number.present? && normalised_bank_detail(bank_account_number) !~ /\A\d{8}\z/
  end

  def bank_sort_code_must_be_six_digits
    errors.add(:bank_sort_code, "Sort code must be 6 digits") if bank_sort_code.present? && normalised_bank_detail(bank_sort_code) !~ /\A\d{6}\z/
  end

  def unique_reference
    loop {
      ref = Reference.new.to_s
      break ref unless self.class.exists?(reference: ref)
    }
  end

  def claim_must_not_be_ineligible
    errors.add(:base, "You’re not eligible for this payment") if eligibility.ineligible?
  end

  def postcode_is_valid
    unless postcode_is_valid?
      errors.add(:postcode, "Enter a postcode in the correct format")
    end
  end

  def postcode_is_valid?
    UKPostcode.parse(postcode).full_valid?
  end

  def date_has_day_month_year_components
    [
      date_of_birth_day,
      date_of_birth_month,
      date_of_birth_year
    ].compact.size
  end

  def date_of_birth_criteria
    if date_of_birth.present?
      errors.add(:date_of_birth, "Date of birth must be in the past") if date_of_birth > Time.zone.today
    else

      errors.add(:date_of_birth, "Date of birth must include a day, month and year in the correct format, for example 01 01 1980") if date_has_day_month_year_components.between?(1, 2)

      begin
        Date.new(date_of_birth_year, date_of_birth_month, date_of_birth_day) if date_has_day_month_year_components == 3
      rescue ArgumentError
        errors.add(:date_of_birth, "Enter a date of birth in the correct format")
      end

      errors.add(:date_of_birth, "Enter your date of birth") if errors[:date_of_birth].empty?
    end

    year = date_of_birth_year || date_of_birth&.year

    if year.present?
      if year < 1000
        errors.add(:date_of_birth, "Year must include 4 numbers")
      elsif year <= 1900
        errors.add(:date_of_birth, "Year must be after 1900")
      end
    end

    errors[:date_of_birth].empty?
  end

  def using_mobile_number_from_tid?
    logged_in_with_tid? && mobile_check == "use" && provide_mobile_number && mobile_number.present?
  end

  def submittable_mobile_details?
    return true unless has_ecp_or_lupp_policy?
    return true if using_mobile_number_from_tid?
    return true if provide_mobile_number && mobile_number.present? && mobile_verified == true
    return true if provide_mobile_number == false && mobile_number.nil? && mobile_verified == false
    return true if provide_mobile_number == false && mobile_verified.nil?

    false
  end

  def submittable_email_details?
    email_address.present? && email_verified == true
  end
end
