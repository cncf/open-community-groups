use serde_json::json;

use super::{EventSurveyAudience, EventSurveyState};

#[test]
fn test_event_survey_audience_uses_kebab_case() {
    assert_eq!(
        serde_json::to_value(EventSurveyAudience::CheckedIn).unwrap(),
        json!("checked-in")
    );
    assert_eq!(
        serde_json::from_value::<EventSurveyAudience>(json!("confirmed")).unwrap(),
        EventSurveyAudience::Confirmed
    );
}

#[test]
fn test_event_survey_state_uses_kebab_case() {
    assert_eq!(
        serde_json::from_value::<EventSurveyState>(json!("scheduled")).unwrap(),
        EventSurveyState::Scheduled
    );
    assert_eq!(EventSurveyState::Open.to_string(), "open");
}
