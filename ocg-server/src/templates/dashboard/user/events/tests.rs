use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::Los_Angeles;
use uuid::Uuid;

use crate::types::{
    dashboard::user::events::{
        UserEventSurveyItem, UserEventSurveyResponse, UserEventSurveysOutput,
    },
    pagination::NavigationLinks,
    questionnaire::{QuestionnaireAnswer, QuestionnaireAnswerValue, QuestionnaireAnswers},
    tests::{sample_user_event_survey, sample_user_event_survey_item},
};

use super::{ListPage, SurveyModal, SurveysPage, survey_date_label};

#[test]
fn test_list_page_hides_surveys_panel_without_surveys() {
    let page = sample_list_page(vec![], 0);

    let html = page.render().unwrap();

    assert!(!html.contains("Surveys to answer"));
    assert!(!html.contains("data-user-event-surveys"));
}

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
        r#"hx-put="/dashboard/user/events/surveys/00000000-0000-0000-0000-000000000001/response""#
    ));
    assert!(html.contains("This survey is anonymous"));
    assert!(!html.contains("This survey is closed or isn't available to you."));
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
fn test_list_page_renders_warning() {
    // Render the list warning about an unavailable survey
    let mut page = sample_list_page(vec![], 0);
    page.warning = Some("This survey is closed or isn't available to you.".to_string());
    let html = page.render().unwrap();

    // Check the warning precedes the page title and no survey opens
    let warning_index = html
        .find("This survey is closed or isn&#39;t available to you.")
        .unwrap();
    let title_index = html.find("My Events").unwrap();
    assert!(warning_index < title_index);
    assert!(!html.contains("data-open-on-load"));
}

#[test]
fn test_list_page_renders_surveys_panel_above_events() {
    // Render a first page with more surveys to load
    let mut closing = sample_user_event_survey_item(Uuid::from_u128(1), false);
    closing.closes_at = Some(Utc.with_ymd_and_hms(2099, 1, 10, 10, 0, 0).unwrap());
    let answered = sample_user_event_survey_item(Uuid::from_u128(2), true);
    let page = sample_list_page(vec![closing, answered], 3);
    let html = page.render().unwrap();

    // Check the panel precedes the events table
    let panel_index = html.find("Surveys to answer").unwrap();
    let table_index = html.find("<table").unwrap();
    assert!(panel_index < table_index);

    // Check each survey loads its modal with its answered state
    assert!(html.contains(
        r#"hx-get="/dashboard/user/events/surveys/00000000-0000-0000-0000-000000000001""#
    ));
    assert!(html.contains(r##"hx-target="#user-event-survey-modal-content""##));
    assert!(html.contains("Not answered"));
    assert!(html.contains("Answered"));
    assert!(html.contains("Edit answers"));
    assert!(html.contains("Closes January 10, 2099 at 10:00 AM UTC"));

    // Check the show more button requests the next page and counts the rest
    assert!(html.contains(r#"hx-get="/dashboard/user/events/surveys?offset=2""#));
    assert!(html.contains("Show more surveys (1 left)"));
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
    survey.response = Some(UserEventSurveyResponse {
        answers: QuestionnaireAnswers {
            answers: vec![QuestionnaireAnswer {
                question_id: Uuid::from_u128(0x5d01),
                value: QuestionnaireAnswerValue::One("More hands-on time".to_string()),
            }],
        },
        created_at: Utc.with_ymd_and_hms(2099, 1, 2, 9, 0, 0).unwrap(),

        updated_at: None,
    });
    let html = SurveyModal { survey }.render().unwrap();

    // Check the saved notice, the answers and the edit controls
    assert!(html.contains("You answered this survey on January 2, 2099 at 9:00 AM UTC."));
    assert!(html.contains("More hands-on time"));
    assert!(html.contains("Save changes"));
    assert!(!html.contains("Submit answers"));
}

#[test]
fn test_surveys_next_offset_returns_none_for_empty_page() {
    let page = SurveysPage {
        surveys: UserEventSurveysOutput {
            surveys: vec![],
            total: 5,
        },

        offset: Some(10),
    };

    assert_eq!(page.surveys_next_offset(), None);
}

#[test]
fn test_surveys_page_omits_show_more_on_last_page() {
    let page = SurveysPage {
        surveys: UserEventSurveysOutput {
            surveys: vec![sample_user_event_survey_item(Uuid::from_u128(3), false)],
            total: 3,
        },

        offset: Some(2),
    };

    let html = page.render().unwrap();

    assert!(html.contains("Session feedback"));
    assert!(!html.contains("Show more"));
    assert!(!html.contains("<section"));
}

#[test]
fn test_surveys_page_renders_next_page_button() {
    let page = SurveysPage {
        surveys: UserEventSurveysOutput {
            surveys: vec![sample_user_event_survey_item(Uuid::from_u128(11), false)],
            total: 12,
        },

        offset: Some(10),
    };

    let html = page.render().unwrap();

    assert!(html.contains(r#"hx-get="/dashboard/user/events/surveys?offset=11""#));
    assert!(html.contains(r#"hx-target="closest li""#));
    assert!(html.contains("Show more surveys (1 left)"));
}

// Helpers.

/// Sample list page with the given surveys panel data.
fn sample_list_page(surveys: Vec<UserEventSurveyItem>, total: usize) -> ListPage {
    ListPage {
        events: vec![],
        navigation_links: NavigationLinks::default(),
        surveys: UserEventSurveysOutput { surveys, total },
        total: 0,

        offset: None,
        survey: None,
        warning: None,
    }
}
