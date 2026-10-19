//! User dashboard event types.

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        event::{
            EventAdmissionOfferSource, EventAdmissionOfferStatus, EventEnrollmentStatus,
            EventSummary,
        },
        pagination::{Pagination, ToRawQuery},
        payments::{EventRefundRequestStatus, ExternalPaymentInfo},
        questionnaire::{
            QuestionnaireAnswers, QuestionnaireQuestion,
            deserialize_required_questionnaire_answers, validate_questionnaire_answers,
        },
    },
    validation::{MAX_PAGINATION_LIMIT, MAX_SURVEY_PAGE_LIMIT},
};

/// Summary of one user event participation.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEvent {
    /// Event summary data.
    pub event: EventSummary,
    /// Whether the user has a paid purchase that blocks dashboard cancellation.
    #[serde(default)]
    pub has_paid_purchase: bool,
    /// Whether this attendee row was created by an organizer invitation.
    #[serde(default)]
    pub manually_invited: bool,
    /// Registration questions configured for the event.
    #[serde(default)]
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Roles the user has in the event.
    #[serde(default)]
    pub roles: Vec<UserEventRole>,

    /// Active admission offer identifier.
    pub admission_offer_id: Option<uuid::Uuid>,
    /// Workflow that created the active admission offer.
    pub admission_offer_source: Option<EventAdmissionOfferSource>,
    /// Current active offer status.
    pub admission_offer_status: Option<EventAdmissionOfferStatus>,
    /// Current or snapshotted offer amount in minor units.
    pub amount_minor: Option<i64>,
    /// Currency used to display the offer amount.
    pub currency_code: Option<String>,
    /// Current enrollment status for the user.
    pub enrollment_status: Option<EventEnrollmentStatus>,
    /// Ticket type assigned to the active offer.
    pub event_ticket_type_id: Option<uuid::Uuid>,
    /// Snapshot of an unpaid external purchase the attendee must complete.
    pub external_payment: Option<ExternalPaymentInfo>,
    /// Active offer expiration time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub offer_expires_at: Option<chrono::DateTime<chrono::Utc>>,
    /// Existing registration answers submitted by the user.
    pub registration_answers: Option<QuestionnaireAnswers>,
    /// Attendee-visible reason for the latest rejected refund request.
    pub refund_rejection_reason: Option<String>,
    /// Latest refund review status for the user's event purchases.
    pub refund_request_status: Option<EventRefundRequestStatus>,
    /// Checkout URL where the user can complete payment.
    pub resume_checkout_url: Option<String>,
    /// Assigned ticket title.
    pub ticket_title: Option<String>,
}

impl UserEvent {
    /// Returns true when attendance can be canceled from the user dashboard.
    pub(crate) fn can_cancel_attendance(&self) -> bool {
        let has_cancelable_enrollment = matches!(
            self.enrollment_status.as_ref(),
            Some(EventEnrollmentStatus::Attendee)
        );
        has_cancelable_enrollment
            && self.roles.as_slice() == [UserEventRole::Attendee]
            && !self.has_paid_purchase
    }

    /// Returns true when an active checkout can be canceled from the user dashboard.
    pub(crate) fn can_cancel_checkout(&self) -> bool {
        self.payment_pending()
    }

    /// Returns true when registration answers can be completed or updated.
    pub(crate) fn can_complete_registration_questions(&self) -> bool {
        self.has_registration_questions_action()
            && (self.manually_invited
                || self.payment_pending()
                || self.event.registration_window_is_open())
    }

    /// Returns the enrollment status badge label, when the row needs one.
    pub(crate) fn enrollment_status_label(&self) -> Option<&'static str> {
        match self.enrollment_status.as_ref()? {
            EventEnrollmentStatus::PendingPayment => Some("Payment pending"),
            EventEnrollmentStatus::RegistrationQuestionsPending => Some("Registration pending"),
            _ => None,
        }
    }

    /// Returns true when the row represents an active admission offer.
    pub(crate) fn has_active_offer(&self) -> bool {
        self.admission_offer_id.is_some() && self.roles.contains(&UserEventRole::Offer)
    }

    /// Returns true when the registration question action applies to the row.
    pub(crate) fn has_registration_questions_action(&self) -> bool {
        !self.registration_questions.is_empty()
            && matches!(
                self.enrollment_status.as_ref(),
                Some(
                    EventEnrollmentStatus::Attendee
                        | EventEnrollmentStatus::PendingPayment
                        | EventEnrollmentStatus::RegistrationQuestionsPending
                )
            )
    }

    /// Returns a disabled tooltip for blocked registration question actions.
    pub(crate) fn registration_questions_disabled_title(&self) -> Option<String> {
        if self.has_registration_questions_action() && !self.can_complete_registration_questions() {
            return self.event.registration_window_unavailable_title();
        }

        None
    }

    /// Returns the registration question action label.
    pub(crate) fn registration_questions_label(&self) -> &'static str {
        if self.registration_questions_pending()
            || (self.payment_pending() && self.registration_answers.is_none())
        {
            "Complete registration"
        } else {
            "Update answers"
        }
    }

    /// Returns true when registration questions are still required.
    pub(crate) fn registration_questions_pending(&self) -> bool {
        matches!(
            self.enrollment_status.as_ref(),
            Some(EventEnrollmentStatus::RegistrationQuestionsPending)
        )
    }

    /// Returns true when payment is still pending.
    fn payment_pending(&self) -> bool {
        matches!(
            self.enrollment_status.as_ref(),
            Some(EventEnrollmentStatus::PendingPayment)
        )
    }
}

/// User's participation role in an event.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub(crate) enum UserEventRole {
    /// User attends the event.
    Attendee,
    /// User hosts the event.
    Host,
    /// User owns an active admission offer.
    Offer,
    /// User speaks at the event or one of its sessions.
    Speaker,
}

impl UserEventRole {
    /// Returns the user-facing role label.
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Attendee => "Attendee",
            Self::Host => "Host",
            Self::Offer => "Event offer",
            Self::Speaker => "Speaker",
        }
    }
}

/// Open event survey a user answers from the dashboard.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurvey {
    /// Whether respondent identities are hidden from the organizers.
    pub anonymous: bool,
    /// Event the survey belongs to.
    pub event: EventSummary,
    /// Survey identifier.
    pub event_survey_id: Uuid,
    /// Questions in definition order.
    pub questions: Vec<QuestionnaireQuestion>,
    /// Revision the answers are given to.
    pub revision: i64,
    /// Survey title.
    pub title: String,

    /// Scheduled closing time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closes_at: Option<DateTime<Utc>>,
    /// Plain text introduction.
    pub description: Option<String>,
    /// Response the user already submitted.
    pub response: Option<UserEventSurveyResponse>,
}

/// Open survey a user can answer, listed in the My Events surveys panel.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurveyItem {
    /// Whether the user already answered the survey.
    pub answered: bool,
    /// Event name.
    pub event_name: String,
    /// Survey identifier.
    pub event_survey_id: Uuid,
    /// Name of the group hosting the event.
    pub group_name: String,
    /// Event timezone.
    pub timezone: Tz,
    /// Survey title.
    pub title: String,

    /// Scheduled closing time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub closes_at: Option<DateTime<Utc>>,
}

/// Response a user submitted to an event survey.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurveyResponse {
    /// Submitted answers.
    pub answers: QuestionnaireAnswers,
    /// First submission time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,

    /// Latest edit time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Filter parameters for the surveys panel pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct UserEventSurveysFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_user_event_surveys_limit")]
    #[garde(range(min = 1, max = MAX_SURVEY_PAGE_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(UserEventSurveysFilters, limit, offset);

/// Paginated surveys panel data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventSurveysOutput {
    /// Open surveys the user can answer, unanswered first.
    pub surveys: Vec<UserEventSurveyItem>,
    /// Total number of surveys before pagination.
    pub total: usize,
}

/// Filter parameters for events pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct UserEventsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(UserEventsFilters, limit, offset);

/// Paginated events response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserEventsOutput {
    /// Events where the user participates or has actionable admission state.
    pub events: Vec<UserEvent>,
    /// Total number of events before pagination.
    pub total: usize,
}

// Form types.

/// Answers to an event survey submitted by a user.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct EventSurveyAnswersForm {
    /// Answers decoded from the form field JSON.
    #[serde(deserialize_with = "deserialize_required_questionnaire_answers")]
    #[garde(custom(validate_questionnaire_answers))]
    pub answers: QuestionnaireAnswers,
    /// Survey revision the answers were given to.
    #[garde(range(min = 1))]
    pub revision: i64,
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone, Utc};
    use garde::Validate;
    use serde_json::json;
    use uuid::Uuid;

    use crate::{
        types::tests::sample_event_summary,
        types::{
            dashboard::USER_EVENT_SURVEYS_PAGINATION_LIMIT,
            event::EventEnrollmentStatus,
            questionnaire::{
                QuestionnaireAnswerValue, QuestionnaireQuestion, QuestionnaireQuestionKind,
            },
        },
        validation::MAX_SURVEY_PAGE_LIMIT,
    };

    use super::{
        EventSurveyAnswersForm, UserEvent, UserEventRole, UserEventSurvey, UserEventSurveysFilters,
    };

    #[test]
    fn can_cancel_attendance_allows_attendee_status() {
        let user_event = sample_user_event();

        assert!(user_event.can_cancel_attendance());
    }

    #[test]
    fn can_cancel_attendance_rejects_other_statuses() {
        let mut user_event = sample_user_event();
        user_event.enrollment_status = Some(EventEnrollmentStatus::Waitlisted);

        assert!(!user_event.can_cancel_attendance());
    }

    #[test]
    fn can_cancel_checkout_allows_pending_payment() {
        let mut user_event = sample_user_event();
        user_event.enrollment_status = Some(EventEnrollmentStatus::PendingPayment);
        user_event.roles = vec![];

        assert!(user_event.can_cancel_checkout());
    }

    #[test]
    fn can_cancel_checkout_rejects_attendee() {
        let user_event = sample_user_event();

        assert!(!user_event.can_cancel_checkout());
    }

    #[test]
    fn can_complete_registration_questions_allows_active_checkout_hold_after_closed_window() {
        let mut user_event = sample_user_event();
        user_event.enrollment_status = Some(EventEnrollmentStatus::PendingPayment);
        user_event.registration_questions = vec![sample_question()];
        user_event.event.registration_ends_at = Some(Utc::now() - Duration::hours(1));

        assert!(user_event.can_complete_registration_questions());
        assert!(user_event.registration_questions_disabled_title().is_none());
        assert_eq!(
            user_event.registration_questions_label(),
            "Complete registration"
        );
    }

    #[test]
    fn can_complete_registration_questions_allows_manual_invitation_after_closed_window() {
        let mut user_event = sample_user_event();
        user_event.manually_invited = true;
        user_event.registration_questions = vec![sample_question()];
        user_event.event.registration_ends_at = Some(Utc::now() - Duration::hours(1));

        assert!(user_event.can_complete_registration_questions());
        assert!(user_event.registration_questions_disabled_title().is_none());
    }

    #[test]
    fn can_complete_registration_questions_rejects_closed_window() {
        let mut user_event = sample_user_event();
        user_event.registration_questions = vec![sample_question()];
        user_event.event.registration_ends_at = Some(Utc::now() - Duration::hours(1));

        assert!(!user_event.can_complete_registration_questions());
        assert!(user_event.registration_questions_disabled_title().is_some());
    }

    #[test]
    fn event_survey_answers_form_deserializes_answers_and_revision() {
        // Deserialize a form with JSON-encoded answers
        let form: EventSurveyAnswersForm = serde_urlencoded::from_str(&format!(
            "answers={}&revision=4",
            encode_answers(&json!({
                "answers": [{
                    "question_id": "00000000-0000-0000-0000-000000000001",
                    "value": "More hands-on time"
                }]
            }))
        ))
        .unwrap();

        // Check the answers and the revision were decoded
        assert_eq!(form.answers.answers.len(), 1);
        assert_eq!(form.answers.answers[0].question_id, Uuid::from_u128(1));
        assert!(matches!(
            &form.answers.answers[0].value,
            QuestionnaireAnswerValue::One(value) if value == "More hands-on time"
        ));
        assert_eq!(form.revision, 4);
        assert!(form.validate().is_ok());
    }

    #[test]
    fn event_survey_answers_form_rejects_blank_answers() {
        let result = serde_urlencoded::from_str::<EventSurveyAnswersForm>("answers=&revision=1");

        assert!(result.is_err());
    }

    #[test]
    fn event_survey_answers_form_rejects_repeated_question() {
        let form: EventSurveyAnswersForm = serde_urlencoded::from_str(&format!(
            "answers={}&revision=1",
            encode_answers(&json!({
                "answers": [
                    {"question_id": "00000000-0000-0000-0000-000000000001", "value": "First"},
                    {"question_id": "00000000-0000-0000-0000-000000000001", "value": "Second"}
                ]
            }))
        ))
        .unwrap();

        assert!(form.validate().is_err());
    }

    #[test]
    fn event_survey_answers_form_rejects_zero_revision() {
        let form: EventSurveyAnswersForm = serde_urlencoded::from_str(&format!(
            "answers={}&revision=0",
            encode_answers(&json!({ "answers": [] }))
        ))
        .unwrap();

        assert!(form.validate().is_err());
    }

    #[test]
    fn has_active_offer_requires_offer_identifier_and_role() {
        let mut user_event = sample_user_event();
        user_event.admission_offer_id = Some(Uuid::from_u128(1));

        assert!(!user_event.has_active_offer());

        user_event.roles = vec![UserEventRole::Offer];

        assert!(user_event.has_active_offer());
    }

    #[test]
    fn user_event_survey_deserializes_database_payload() {
        // Deserialize a survey in the shape returned by get_user_event_survey
        let event =
            serde_json::to_value(sample_event_summary(Uuid::from_u128(2), Uuid::from_u128(3)))
                .unwrap();
        let survey: UserEventSurvey = serde_json::from_value(json!({
            "anonymous": false,
            "event": event,
            "event_survey_id": "00000000-0000-0000-0000-000000000001",
            "questions": [{
                "id": "00000000-0000-0000-0000-000000000004",
                "kind": "free-text",
                "prompt": "What should we improve?",
                "required": true
            }],
            "revision": 4,
            "title": "Session feedback",

            "closes_at": 4_102_444_800_i64,
            "description": null,
            "response": {
                "answers": {"answers": [{
                    "question_id": "00000000-0000-0000-0000-000000000004",
                    "value": "More hands-on time"
                }]},
                "created_at": 4_099_770_000_i64,
                "updated_at": null
            }
        }))
        .unwrap();

        // Check the survey fields
        assert!(!survey.anonymous);
        assert_eq!(survey.event.event_id, Uuid::from_u128(2));
        assert_eq!(survey.event_survey_id, Uuid::from_u128(1));
        assert_eq!(survey.questions.len(), 1);
        assert_eq!(survey.revision, 4);
        assert_eq!(survey.title, "Session feedback");
        assert_eq!(
            survey.closes_at,
            Utc.with_ymd_and_hms(2100, 1, 1, 0, 0, 0).single()
        );
        assert!(survey.description.is_none());

        // Check the stored response without an edit time
        let response = survey.response.unwrap();
        assert_eq!(response.answers.answers.len(), 1);
        assert_eq!(
            response.created_at,
            Utc.with_ymd_and_hms(2099, 12, 1, 1, 0, 0).unwrap()
        );
        assert!(response.updated_at.is_none());
    }

    #[test]
    fn user_event_surveys_filters_accept_page_limit() {
        let filters = UserEventSurveysFilters {
            limit: Some(MAX_SURVEY_PAGE_LIMIT),
            offset: Some(10),
        };

        assert!(filters.validate().is_ok());
    }

    #[test]
    fn user_event_surveys_filters_apply_default_bounds() {
        let filters: UserEventSurveysFilters = serde_qs::from_str("").unwrap();

        assert_eq!(filters.limit, Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT));
        assert_eq!(filters.offset, Some(0));
    }

    #[test]
    fn user_event_surveys_filters_reject_empty_pages() {
        let filters: UserEventSurveysFilters = serde_qs::from_str("limit=0").unwrap();

        assert!(filters.validate().is_err());
    }

    #[test]
    fn user_event_surveys_filters_reject_limit_above_page_limit() {
        let filters = UserEventSurveysFilters {
            limit: Some(MAX_SURVEY_PAGE_LIMIT + 1),
            offset: None,
        };

        assert!(filters.validate().is_err());
    }

    // Helpers.

    /// Encodes an answers payload as a form field value.
    fn encode_answers(answers: &serde_json::Value) -> String {
        serde_urlencoded::to_string([("v", answers.to_string())])
            .unwrap()
            .trim_start_matches("v=")
            .to_string()
    }

    /// Sample free-text registration question.
    fn sample_question() -> QuestionnaireQuestion {
        QuestionnaireQuestion {
            id: Uuid::new_v4(),
            kind: QuestionnaireQuestionKind::FreeText,
            prompt: "Any dietary notes?".to_string(),
            required: false,

            options: vec![],
        }
    }

    /// Sample user event row with cancelable attendee attendance.
    fn sample_user_event() -> UserEvent {
        UserEvent {
            event: sample_event_summary(Uuid::new_v4(), Uuid::new_v4()),
            has_paid_purchase: false,
            manually_invited: false,
            registration_questions: vec![],
            roles: vec![UserEventRole::Attendee],

            admission_offer_id: None,
            admission_offer_source: None,
            admission_offer_status: None,
            amount_minor: None,
            currency_code: None,
            enrollment_status: Some(EventEnrollmentStatus::Attendee),
            event_ticket_type_id: None,
            external_payment: None,
            offer_expires_at: None,
            registration_answers: None,
            refund_rejection_reason: None,
            refund_request_status: None,
            resume_checkout_url: None,
            ticket_title: None,
        }
    }
}
