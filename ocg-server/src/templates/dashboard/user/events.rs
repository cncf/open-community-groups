//! Templates for user upcoming events.

use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;

use crate::types::{
    dashboard::user::events::{UserEvent, UserEventSurvey, UserEventSurveysOutput},
    pagination,
    questionnaire::QuestionnaireAnswers,
};

#[cfg(test)]
mod tests;

// Pages templates.

/// List page for the user upcoming events section.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/events_list.html")]
pub(crate) struct ListPage {
    /// Events where the user participates.
    pub events: Vec<UserEvent>,
    /// Pagination links for the events list.
    pub navigation_links: pagination::NavigationLinks,
    /// First page of the open surveys the user can answer.
    pub surveys: UserEventSurveysOutput,
    /// Total number of events before pagination.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Survey opened on load, requested by the link in its opening email.
    pub survey: Option<Box<UserEventSurvey>>,
    /// Warning shown when the requested survey can't be answered.
    pub warning: Option<String>,
}

impl ListPage {
    /// Returns the offset of the next page of surveys, when more remain.
    pub(crate) fn surveys_next_offset(&self) -> Option<usize> {
        surveys_next_offset(&self.surveys, None)
    }

    /// Returns the number of surveys after this page.
    pub(crate) fn surveys_remaining(&self) -> usize {
        surveys_remaining(&self.surveys, None)
    }
}

/// Page of the surveys panel loaded by its "Show more" button.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/events_surveys.html")]
pub(crate) struct SurveysPage {
    /// Page of open surveys the user can answer.
    pub surveys: UserEventSurveysOutput,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}

impl SurveysPage {
    /// Returns the offset of the next page of surveys, when more remain.
    pub(crate) fn surveys_next_offset(&self) -> Option<usize> {
        surveys_next_offset(&self.surveys, self.offset)
    }

    /// Returns the number of surveys after this page.
    pub(crate) fn surveys_remaining(&self) -> usize {
        surveys_remaining(&self.surveys, self.offset)
    }
}

/// Content of the survey modal, where the user answers an open survey.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/events_survey.html")]
pub(crate) struct SurveyModal {
    /// Open survey the user can answer.
    pub survey: UserEventSurvey,
}

// Helpers.

/// Returns the answers the user already submitted to a survey, if any.
pub(crate) fn survey_answers(survey: &UserEventSurvey) -> Option<&QuestionnaireAnswers> {
    survey.response.as_ref().map(|response| &response.answers)
}

/// Formats a survey date in the event timezone. Askama passes both values by
/// reference.
#[allow(clippy::trivially_copy_pass_by_ref)]
pub(crate) fn survey_date_label(value: &DateTime<Utc>, timezone: &Tz) -> String {
    value
        .with_timezone(timezone)
        .format("%B %-e, %Y at %-I:%M %p %Z")
        .to_string()
}

/// Returns the offset of the page that follows a page of surveys, when more
/// surveys remain.
fn surveys_next_offset(surveys: &UserEventSurveysOutput, offset: Option<usize>) -> Option<usize> {
    let next_offset = offset.unwrap_or_default() + surveys.surveys.len();
    (next_offset < surveys.total && !surveys.surveys.is_empty()).then_some(next_offset)
}

/// Returns the number of surveys that follow a page of surveys.
fn surveys_remaining(surveys: &UserEventSurveysOutput, offset: Option<usize>) -> usize {
    surveys
        .total
        .saturating_sub(offset.unwrap_or_default() + surveys.surveys.len())
}
