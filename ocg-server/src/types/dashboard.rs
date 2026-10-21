//! Dashboard type definitions.

pub mod common;
pub mod community;
pub mod group;
pub mod user;

/// Default pagination limit for dashboard lists.
pub(crate) const DASHBOARD_PAGINATION_LIMIT: usize = 50;

/// Default page size of the individual responses to a survey.
pub(crate) const EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT: usize = 20;

/// Default page size of the answers to a free-text survey question.
pub(crate) const EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT: usize = 10;

/// Default page size of the Surveys tab in the user dashboard.
pub(crate) const USER_EVENT_SURVEYS_PAGINATION_LIMIT: usize = 10;

/// Default survey responses pagination limit for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_event_survey_responses_limit() -> Option<usize> {
    Some(EVENT_SURVEY_RESPONSES_PAGINATION_LIMIT)
}

/// Default survey text answers pagination limit for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_event_survey_text_answers_limit() -> Option<usize> {
    Some(EVENT_SURVEY_TEXT_ANSWERS_PAGINATION_LIMIT)
}

/// Default dashboard pagination limit for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_limit() -> Option<usize> {
    Some(DASHBOARD_PAGINATION_LIMIT)
}

/// Default dashboard pagination offset for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_offset() -> Option<usize> {
    Some(0)
}

/// Default user Surveys tab pagination limit for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_user_event_surveys_limit() -> Option<usize> {
    Some(USER_EVENT_SURVEYS_PAGINATION_LIMIT)
}
