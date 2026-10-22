//! Templates for the user dashboard Surveys tab.

use askama::Template;
use chrono::{DateTime, Utc};
use chrono_tz::Tz;

use crate::types::{
    dashboard::user::surveys::{UserEventSurvey, UserEventSurveyItem},
    pagination,
    questionnaire::QuestionnaireAnswers,
};

#[cfg(test)]
mod tests;

// Pages templates.

/// List page for the user dashboard Surveys tab.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/surveys_list.html")]
pub(crate) struct ListPage {
    /// Pagination links for the surveys list.
    pub navigation_links: pagination::NavigationLinks,
    /// Dashboard URL of the current page, reloaded after answers are saved so
    /// the menu badge counts the surveys left to answer.
    pub refresh_url: String,
    /// Open surveys the user can answer, followed by the closed surveys the
    /// user answered.
    pub surveys: Vec<UserEventSurveyItem>,
    /// Total number of surveys before pagination.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Survey opened on load, requested by the link in its opening email.
    pub survey: Option<Box<UserEventSurvey>>,
    /// Warning shown when the requested survey isn't available.
    pub warning: Option<String>,
}

/// Content of the survey modal, where the user answers an open survey or
/// reviews the answers given to a closed one.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/surveys_modal.html")]
pub(crate) struct SurveyModal {
    /// Survey the user answers or reviews.
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
