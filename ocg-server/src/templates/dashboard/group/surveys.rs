//! Templates for the event surveys tab in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use serde_json::json;
use uuid::Uuid;

use crate::{
    templates::{
        filters,
        helpers::{DATE_FORMAT, NOT_APPLICABLE_LABEL, count_label, percent_label},
    },
    types::{
        dashboard::group::surveys::{
            EventSurveyFull, EventSurveyResponsesOutput, EventSurveyResults,
            EventSurveyStatusAction, EventSurveySummary, EventSurveyTextAnswers,
        },
        event::EventSummary,
        event_survey::{EventSurveyAudience, EventSurveyState},
        pagination,
    },
};

#[cfg(test)]
mod tests;

/// Display format of the survey dates, in the event timezone.
const DISPLAY_DATE_FORMAT: &str = "%B %-e, %Y %-I:%M %p %Z";

/// Responses below which anonymous results may still identify respondents.
const FEW_RESPONSES_THRESHOLD: i64 = 5;

// Pages templates.

/// Survey form page template, used to add and update surveys.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/surveys_form.html")]
pub(crate) struct FormPage {
    /// Whether the current user can manage the event surveys.
    pub can_manage_surveys: bool,
    /// Event the survey belongs to.
    pub event: EventSummary,

    /// Survey being updated; none on the add form.
    pub survey: Option<EventSurveyFull>,
}

impl FormPage {
    /// Returns the survey anonymity, anonymous by default.
    pub(crate) fn anonymous(&self) -> bool {
        self.survey.as_ref().is_none_or(|survey| survey.summary.anonymous)
    }

    /// Returns whether an anonymous survey must stay anonymous because it
    /// opened or its opening email was handled.
    pub(crate) fn anonymous_locked(&self) -> bool {
        self.survey
            .as_ref()
            .is_some_and(|survey| survey.summary.anonymous_locked)
    }

    /// Returns the survey audience, confirmed attendees by default.
    pub(crate) fn audience(&self) -> EventSurveyAudience {
        self.survey
            .as_ref()
            .map(|survey| survey.summary.audience)
            .unwrap_or_default()
    }

    /// Returns the scheduled closing time as a datetime-local value in the
    /// event timezone.
    pub(crate) fn closes_at_value(&self) -> String {
        datetime_local_value(
            self.survey.as_ref().and_then(|survey| survey.summary.closes_at),
            self.event.timezone,
        )
    }

    /// Returns whether responses lock the questions, audience and anonymity.
    pub(crate) fn locked(&self) -> bool {
        self.survey.as_ref().is_some_and(|survey| survey.summary.locked)
    }

    /// Returns the custom opening time as a datetime-local value in the event
    /// timezone.
    pub(crate) fn opens_at_value(&self) -> String {
        datetime_local_value(
            self.survey.as_ref().and_then(|survey| survey.opens_at),
            self.event.timezone,
        )
    }
}

/// Event surveys list page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/surveys_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage the event surveys.
    pub can_manage_surveys: bool,
    /// Event the surveys belong to.
    pub event: EventSummary,
    /// Time the page is rendered, used to describe pending transitions.
    pub now: DateTime<Utc>,
    /// Surveys of the event in creation order.
    pub surveys: Vec<EventSurveySummary>,
}

impl ListPage {
    /// Returns whether the event cannot get another survey.
    pub(crate) fn limit_reached(&self) -> bool {
        EventSurveySummary::limit_reached(&self.surveys)
    }
}

/// Individual responses page template of an identified survey.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/surveys_responses.html")]
pub(crate) struct ResponsesPage {
    /// Event the survey belongs to.
    pub event: EventSummary,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Page of responses.
    pub responses: EventSurveyResponsesOutput,
    /// Survey the responses were submitted to.
    pub survey: EventSurveyFull,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}

/// Aggregated results page template of a survey.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/surveys_results.html")]
pub(crate) struct ResultsPage {
    /// Event the survey belongs to.
    pub event: EventSummary,
    /// Survey results.
    pub results: EventSurveyResults,
}

/// Page of answers to a free-text question, appended by "Show more".
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/surveys_text_answers.html")]
pub(crate) struct TextAnswersPage {
    /// Page of answers.
    pub answers: EventSurveyTextAnswers,
    /// Event the survey belongs to.
    pub event_id: Uuid,
    /// Survey the question belongs to.
    pub event_survey_id: Uuid,
    /// Number of answers per page.
    pub limit: usize,
    /// Free-text question identifier.
    pub question_id: Uuid,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}

impl TextAnswersPage {
    /// Returns the offset of the next page, when more answers remain.
    pub(crate) fn next_offset(&self) -> Option<usize> {
        let next_offset = self.offset.unwrap_or_default() + self.answers.answers.len();
        (next_offset < self.answers.total && !self.answers.answers.is_empty())
            .then_some(next_offset)
    }

    /// Returns the number of answers after this page.
    pub(crate) fn remaining(&self) -> usize {
        self.answers
            .total
            .saturating_sub(self.offset.unwrap_or_default() + self.answers.answers.len())
    }
}

// Types.

/// Reason a draft survey cannot be marked ready yet, mirroring the checks the
/// database applies to the schedule.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MarkReadyBlocker {
    /// The closing date is not after the effective opening.
    ClosesBeforeOpening,
    /// The closing date is not in the future.
    ClosingDatePassed,
    /// The survey has no questions.
    NoQuestions,
}

impl MarkReadyBlocker {
    /// Returns the short hint shown under the survey state in the list.
    pub(crate) fn hint(self) -> &'static str {
        match self {
            Self::ClosesBeforeOpening => "Closes before it opens",
            Self::ClosingDatePassed => "Closing date has passed",
            Self::NoQuestions => "No questions yet",
        }
    }

    /// Returns why the Mark ready button is disabled.
    pub(crate) fn reason(self) -> &'static str {
        match self {
            Self::ClosesBeforeOpening => "Edit the closing date so it is after the survey opens.",
            Self::ClosingDatePassed => "Edit the closing date to mark the survey ready.",
            Self::NoQuestions => "Add a question before marking the survey ready.",
        }
    }
}

/// Status button shown in a survey row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SurveyStatusAction {
    /// Transition requested by the button.
    pub action: EventSurveyStatusAction,
    /// Confirmation message shown before the transition.
    pub confirm_message: String,
    /// Label of the confirmation button.
    pub confirm_text: &'static str,
    /// Icon name of the button.
    pub icon: &'static str,
    /// Button label.
    pub label: &'static str,
    /// Values sent with the status request.
    pub request_values: String,
    /// Message shown after a successful transition.
    pub success_message: &'static str,

    /// Reason the transition is unavailable; none when it is enabled.
    pub disabled_reason: Option<&'static str>,
}

// Helpers.

/// Returns the closing date of a survey for the list, in the event timezone.
pub(crate) fn closes_label(survey: &EventSurveySummary, timezone: Tz) -> String {
    survey.closes_at.map_or_else(
        || "No closing date".to_string(),
        |closes_at| format_date(closes_at, timezone),
    )
}

/// Returns whether an anonymous survey has so few responses that its answers
/// may still identify respondents.
pub(crate) fn few_anonymous_responses(survey: &EventSurveySummary) -> bool {
    survey.anonymous
        && survey.responses_count > 0
        && survey.responses_count < FEW_RESPONSES_THRESHOLD
}

/// Formats a date for display in the event timezone.
pub(crate) fn format_date(date: DateTime<Utc>, timezone: Tz) -> String {
    date.with_timezone(&timezone).format(DISPLAY_DATE_FORMAT).to_string()
}

/// Returns what keeps a draft survey from being marked ready, if anything.
///
/// Surveys in other states are never blocked.
pub(crate) fn mark_ready_blocker(
    survey: &EventSurveySummary,
    now: DateTime<Utc>,
) -> Option<MarkReadyBlocker> {
    // Only drafts can be marked ready
    if survey.state != EventSurveyState::Draft {
        return None;
    }

    // Require at least one question
    if survey.questions_count == 0 {
        return Some(MarkReadyBlocker::NoQuestions);
    }

    // Require a configured closing date in the future and after the opening
    let closes_at = survey.closes_at?;
    if closes_at <= now {
        Some(MarkReadyBlocker::ClosingDatePassed)
    } else if survey
        .effective_opens_at
        .is_some_and(|opens_at| closes_at <= opens_at)
    {
        Some(MarkReadyBlocker::ClosesBeforeOpening)
    } else {
        None
    }
}

/// Returns when a draft or scheduled survey opens, in the event timezone.
///
/// The effective opening is missing only while the event has no dates. Once
/// it has passed, the survey still waits for the event to be published and,
/// for drafts, to be marked ready.
pub(crate) fn opening_label(
    survey: &EventSurveySummary,
    event: &EventSummary,
    now: DateTime<Utc>,
) -> String {
    match survey.effective_opens_at {
        None => "Opens once the event has a date".to_string(),
        Some(opens_at) if opens_at > now => {
            format!("Opens {}", format_date(opens_at, event.timezone))
        }
        Some(_) if !event.published => "Opens once the event is published".to_string(),
        Some(_) if survey.state == EventSurveyState::Draft => "Opens when marked ready".to_string(),
        Some(_) => "Opens now".to_string(),
    }
}

/// Returns the responses of a survey, for example `12 / 40 (30%)`.
///
/// Counts eligible respondents over eligible attendees, adding the stored
/// total when respondents who are no longer eligible also answered, and shows
/// a dash when nobody is eligible.
pub(crate) fn responses_label(survey: &EventSurveySummary) -> String {
    // Describe the eligible respondents and their response rate
    let label = survey.response_rate().map_or_else(
        || NOT_APPLICABLE_LABEL.to_string(),
        |rate| {
            format!(
                "{} / {} ({})",
                count_label(survey.eligible_respondents_count),
                count_label(survey.eligible_count),
                percent_label(Some(rate))
            )
        },
    );

    // Add the stored total when it differs from the eligible respondents
    if survey.responses_count == survey.eligible_respondents_count {
        label
    } else {
        format!("{label} · {} total", count_label(survey.responses_count))
    }
}

/// Returns the status button of a survey row, chosen by its state.
pub(crate) fn status_action(
    survey: &EventSurveySummary,
    event: &EventSummary,
    now: DateTime<Utc>,
) -> SurveyStatusAction {
    match survey.state {
        // Drafts confirm when the opening email is sent
        EventSurveyState::Draft => {
            let expected_effective_opens_at = survey
                .effective_opens_at
                .map(|opens_at| opens_at.timestamp().to_string())
                .unwrap_or_default();
            SurveyStatusAction {
                action: EventSurveyStatusAction::MarkReady,
                confirm_message: mark_ready_message(survey, event, now),
                confirm_text: "Mark ready",
                icon: "check",
                label: "Mark ready",
                request_values: json!({
                    "action": EventSurveyStatusAction::MarkReady.to_string(),
                    "expected_effective_opens_at": expected_effective_opens_at,
                    "revision": survey.revision.to_string(),
                })
                .to_string(),
                success_message: "You have successfully marked the survey ready.",

                disabled_reason: mark_ready_blocker(survey, now).map(MarkReadyBlocker::reason),
            }
        }
        // Scheduled surveys go back to draft only before anyone was emailed
        EventSurveyState::Scheduled => SurveyStatusAction {
            action: EventSurveyStatusAction::BackToDraft,
            confirm_message:
                "Move this survey back to draft? It will not open until it is marked ready again."
                    .to_string(),
            confirm_text: "Back to draft",
            icon: "undo",
            label: "Back to draft",
            request_values: status_request_values(EventSurveyStatusAction::BackToDraft, survey),
            success_message: "You have successfully moved the survey back to draft.",

            disabled_reason: if survey.open_notification_processed_at.is_some() {
                Some("The opening email was already sent.")
            } else if survey.responses_count > 0 {
                Some("The survey already has responses.")
            } else {
                None
            },
        },
        // Open surveys can be closed at any time
        EventSurveyState::Open => SurveyStatusAction {
            action: EventSurveyStatusAction::Close,
            confirm_message:
                "Close this survey? Attendees will no longer be able to answer or edit their answers."
                    .to_string(),
            confirm_text: "Close",
            icon: "close",
            label: "Close",
            request_values: status_request_values(EventSurveyStatusAction::Close, survey),
            success_message: "You have successfully closed the survey.",

            disabled_reason: None,
        },
        // Closed surveys reopen unless their closing date has passed
        EventSurveyState::Closed => SurveyStatusAction {
            action: EventSurveyStatusAction::Reopen,
            confirm_message:
                "Reopen this survey? Attendees will be able to answer it again. No new email is sent."
                    .to_string(),
            confirm_text: "Reopen",
            icon: "refresh",
            label: "Reopen",
            request_values: status_request_values(EventSurveyStatusAction::Reopen, survey),
            success_message: "You have successfully reopened the survey.",

            disabled_reason: survey
                .closes_at
                .is_some_and(|closes_at| closes_at <= now)
                .then_some("Edit the closing date to reopen."),
        },
    }
}

/// Formats an optional time as a datetime-local value in the event timezone.
fn datetime_local_value(date: Option<DateTime<Utc>>, timezone: Tz) -> String {
    date.map(|date| date.with_timezone(&timezone).format(DATE_FORMAT).to_string())
        .unwrap_or_default()
}

/// Returns the Mark ready confirmation, with the attendees currently emailed
/// and when the opening email is sent. Test events never email attendees.
fn mark_ready_message(
    survey: &EventSurveySummary,
    event: &EventSummary,
    now: DateTime<Utc>,
) -> String {
    // Explain that test events send no email
    if event.test_event {
        return "Mark this survey ready? Test events do not email attendees.".to_string();
    }

    // Describe when the opening email is sent
    let when = match survey.effective_opens_at {
        None => "once the event has a date and ends".to_string(),
        Some(opens_at) if opens_at > now => format!("on {}", format_date(opens_at, event.timezone)),
        Some(_) if !event.published => "once the event is published".to_string(),
        Some(_) => "now".to_string(),
    };
    format!(
        "This will email eligible attendees (currently {}) {when}.",
        count_label(survey.eligible_count)
    )
}

/// Returns the values sent with a status request without a confirmed opening.
fn status_request_values(action: EventSurveyStatusAction, survey: &EventSurveySummary) -> String {
    json!({
        "action": action.to_string(),
        "revision": survey.revision.to_string(),
    })
    .to_string()
}
