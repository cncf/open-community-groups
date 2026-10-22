use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::Los_Angeles;
use uuid::Uuid;

use crate::types::{
    dashboard::user::surveys::{UserEventSurveyItem, UserEventSurveyResponse},
    event_survey::EventSurveyState,
    pagination::NavigationLinks,
    questionnaire::{QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers},
    tests::{sample_user_event_survey, sample_user_event_survey_item},
};

use super::{ListPage, SurveyModal, survey_date_label};

#[test]
fn test_list_page_opens_requested_survey_on_load() {
    // Render the list with the survey an opening email links to
    let event_survey_id = Uuid::from_u128(1);
    let mut page = sample_list_page(vec![], 0);
    page.survey = Some(Box::new(sample_user_event_survey(
        event_survey_id,
        Uuid::from_u128(2),
    )));
    let html = page.render().unwrap();

    // Check the modal opens on load with the survey form
    assert!(html.contains("data-open-on-load"));
    assert!(html.contains(r#"id="user-event-survey-title""#));
    assert!(html.contains(
        r#"hx-put="/dashboard/user/surveys/00000000-0000-0000-0000-000000000001/response""#
    ));
    assert!(html.contains("This survey is anonymous"));
    assert!(!html.contains("This survey is closed or isn&#39;t available to you."));
}

#[test]
fn test_list_page_renders_empty_state() {
    let page = sample_list_page(vec![], 0);

    let html = page.render().unwrap();

    assert!(html.contains("No surveys yet"));
    assert!(!html.contains("data-user-event-survey=\""));
}

#[test]
fn test_list_page_renders_refresh_after_saved_answers() {
    let page = sample_list_page(vec![], 0);

    let html = page.render().unwrap();

    assert!(html.contains(r#"hx-get="/dashboard/user?tab=surveys&#38;offset=10""#));
    assert!(html.contains(r#"hx-trigger="refresh-user-surveys from:body""#));
    assert!(html.contains(r##"hx-target="#dashboard-layout""##));
    assert!(html.contains(r##"hx-select="#dashboard-layout""##));
}

#[test]
fn test_list_page_renders_survey_modal_shell_closed() {
    let page = sample_list_page(vec![], 0);

    let html = page.render().unwrap();

    assert!(html.contains(r#"id="user-event-survey-modal""#));
    assert!(html.contains(r#"id="user-event-survey-modal-content""#));
    assert!(!html.contains("data-open-on-load"));
    assert!(!html.contains("data-user-event-survey-form"));
}

#[test]
fn test_list_page_renders_surveys_by_state() {
    // Render an unanswered survey closing soon, an answered one and a closed one
    let mut closing = sample_user_event_survey_item(Uuid::from_u128(1), false);
    closing.closes_at = Some(Utc.with_ymd_and_hms(2099, 1, 10, 10, 0, 0).unwrap());
    let answered = sample_user_event_survey_item(Uuid::from_u128(2), true);
    let mut closed = sample_user_event_survey_item(Uuid::from_u128(3), true);
    closed.closed_at = Some(Utc.with_ymd_and_hms(2025, 5, 4, 8, 0, 0).unwrap());
    closed.state = EventSurveyState::Closed;
    let page = sample_list_page(vec![closing, answered, closed], 3);
    let html = page.render().unwrap();

    // Check each survey loads its modal
    assert!(
        html.contains(r#"hx-get="/dashboard/user/surveys/00000000-0000-0000-0000-000000000001""#)
    );
    assert!(html.contains(r##"hx-target="#user-event-survey-modal-content""##));
    assert!(html.contains("1 - 3 of <span class=\"font-semibold\">3</span>"));

    // Check the status, date and action of the unanswered survey
    let closing_row = survey_row(&html, Uuid::from_u128(1));
    assert!(closing_row.contains("To answer"));
    assert!(closing_row.contains("Closes Jan 10, 2099 at 10:00 AM UTC"));
    assert!(!closing_row.contains("Edit answers"));
    assert!(!closing_row.contains("View answers"));

    // Check the status, date and action of the answered survey
    let answered_row = survey_row(&html, Uuid::from_u128(2));
    assert!(answered_row.contains("Answered"));
    assert!(answered_row.contains("No closing date"));
    assert!(answered_row.contains("Edit answers"));

    // Check the status, date and action of the closed survey
    let closed_row = survey_row(&html, Uuid::from_u128(3));
    assert!(closed_row.contains("Closed May 4, 2025 at 8:00 AM UTC"));
    assert!(closed_row.contains("View answers"));
    assert!(!closed_row.contains("Edit answers"));
}

#[test]
fn test_list_page_renders_warning() {
    // Render the list warning about an unavailable survey
    let mut page = sample_list_page(vec![], 0);
    page.warning = Some("This survey is closed or isn't available to you.".to_string());
    let html = page.render().unwrap();

    // Check the warning precedes the page title and no survey opens
    let warning_index = html
        .find("This survey is closed or isn&#39;t available to you.")
        .unwrap();
    let title_index = html.find("Feedback surveys about events you attended").unwrap();
    assert!(warning_index < title_index);
    assert!(!html.contains("data-open-on-load"));
}

#[test]
fn test_survey_date_label_uses_event_timezone() {
    let value = Utc.with_ymd_and_hms(2030, 3, 6, 7, 30, 0).unwrap();

    assert_eq!(
        survey_date_label(&value, &Los_Angeles),
        "March 5, 2030 at 11:30 PM PST"
    );
    assert_eq!(
        survey_date_label(&value, &chrono_tz::UTC),
        "March 6, 2030 at 7:30 AM UTC"
    );
}

#[test]
fn test_survey_modal_renders_closed_survey_read_only() {
    // Render a closed survey the user answered
    let mut survey = sample_user_event_survey(Uuid::from_u128(1), Uuid::from_u128(2));
    survey.closed_at = Some(Utc.with_ymd_and_hms(2025, 5, 4, 8, 0, 0).unwrap());
    survey.response = Some(sample_response());
    survey.state = EventSurveyState::Closed;
    let html = SurveyModal { survey }.render().unwrap();

    // Check the closing notice and the answers without edit controls
    assert!(html.contains("data-user-event-survey-answers"));
    assert!(html.contains("Closed on May 4, 2025 at 8:00 AM UTC"));
    assert!(html.contains("You answered this survey on January 2, 2099 at 9:00 AM UTC."));
    assert!(html.contains("This survey is closed, so your answers can no longer be changed."));
    assert!(html.contains("More hands-on time"));
    assert!(html.contains("data-user-event-survey-close"));
    assert!(!html.contains("data-user-event-survey-form"));
    assert!(!html.contains("hx-put"));
    assert!(!html.contains("<textarea"));
    assert!(!html.contains("Save changes"));
}

#[test]
fn test_survey_modal_renders_identified_survey_without_response() {
    // Render an identified survey with a closing date and no response
    let mut survey = sample_user_event_survey(Uuid::from_u128(1), Uuid::from_u128(2));
    survey.anonymous = false;
    survey.closes_at = Some(Utc.with_ymd_and_hms(2099, 1, 10, 10, 0, 0).unwrap());
    let html = SurveyModal { survey }.render().unwrap();

    // Check the survey details and the first submission controls
    assert!(html.contains("Session feedback"));
    assert!(html.contains("Closes on January 10, 2099 at 10:00 AM UTC"));
    assert!(html.contains("Tell us how it went."));
    assert!(html.contains("This survey is not anonymous"));
    assert!(html.contains(r#"<input type="hidden" name="revision" value="4">"#));
    assert!(html.contains("Submit answers"));
    assert!(!html.contains("data-survey-response-saved"));
}

#[test]
fn test_survey_modal_renders_saved_response() {
    // Render a survey the user already answered
    let mut survey = sample_user_event_survey(Uuid::from_u128(1), Uuid::from_u128(2));
    survey.response = Some(sample_response());
    let html = SurveyModal { survey }.render().unwrap();

    // Check the saved notice, the answers and the edit controls
    assert!(html.contains("You answered this survey on January 2, 2099 at 9:00 AM UTC."));
    assert!(html.contains("More hands-on time"));
    assert!(html.contains("Save changes"));
    assert!(!html.contains("Submit answers"));
    assert!(!html.contains("data-user-event-survey-answers"));
}

// Helpers.

/// Sample list page with the given surveys.
fn sample_list_page(surveys: Vec<UserEventSurveyItem>, total: usize) -> ListPage {
    ListPage {
        navigation_links: NavigationLinks::default(),
        refresh_url: "/dashboard/user?tab=surveys&offset=10".to_string(),
        surveys,
        total,

        offset: None,
        survey: None,
        warning: None,
    }
}

/// Sample response answering the required question of the sample survey.
fn sample_response() -> UserEventSurveyResponse {
    UserEventSurveyResponse {
        answers: QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: Uuid::from_u128(0x5d01),
                value: QuestionnaireAnswerValue::One("More hands-on time".to_string()),
            }],
        },
        created_at: Utc.with_ymd_and_hms(2099, 1, 2, 9, 0, 0).unwrap(),

        updated_at: None,
    }
}

/// Returns the table row rendered for a survey.
fn survey_row(html: &str, event_survey_id: Uuid) -> &str {
    let start = html
        .find(&format!(r#"data-user-event-survey="{event_survey_id}""#))
        .unwrap();
    let end = start + html[start..].find("</tr>").unwrap();

    &html[start..end]
}
