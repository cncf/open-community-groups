use chrono::{TimeZone, Utc};
use serde_json::json;

use crate::types::{event_survey::EventSurveyState, tests::sample_event_analytics};

use super::*;

#[test]
fn test_check_in_rate_divides_check_ins_by_registrations() {
    let stats = sample_event_analytics();

    assert_eq!(stats.check_in_rate(), Some(0.75));
}

#[test]
fn test_check_in_rate_is_none_without_registrations() {
    let mut stats = sample_event_analytics();
    stats.enrollment.checked_in = 0;
    stats.enrollment.registrations = 0;

    assert_eq!(stats.check_in_rate(), None);
}

#[test]
fn test_check_in_stats_has_activity_requires_a_check_in() {
    let mut check_ins = sample_event_analytics().check_ins;
    assert!(check_ins.has_activity());

    check_ins.bins = vec![(1_710_087_300_000, 0)];
    assert!(!check_ins.has_activity());
}

#[test]
fn test_combinations_remainder_count_subtracts_listed_combinations() {
    let mut utm = sample_event_analytics().utm;
    assert_eq!(utm.combinations_remainder_count(), 0);

    utm.combinations_total_count = 103;
    assert_eq!(utm.combinations_remainder_count(), 102);
}

#[test]
fn test_conversion_rate_divides_registrations_by_views() {
    let stats = sample_event_analytics();

    assert_eq!(stats.conversion_rate(), Some(0.2));
}

#[test]
fn test_conversion_rate_is_none_without_views() {
    let mut stats = sample_event_analytics();
    stats.traffic.views_total = 0;

    assert_eq!(stats.conversion_rate(), None);
}

#[test]
fn test_conversion_rate_is_not_capped() {
    let mut stats = sample_event_analytics();
    stats.traffic.views_total = 2;

    assert_eq!(stats.conversion_rate(), Some(2.0));
}

#[test]
fn test_deserializes_database_payload() {
    // Setup a payload shaped like the database function output
    let payload = json!({
        "audience": {
            "questions": [],
            "window_end_capped": false,
            "window_end_inferred": true,
            "window_start_inferred": true,
            "members_joined_in_window": null,
            "members_joined_in_window_registered": null,
            "new_attendees": null,
            "returning_attendees": null,
            "window_ends_at": null,
            "window_starts_at": null
        },
        "check_ins": {"bin_minutes": 15, "bins": [], "outside_range": 0},
        "enrollment": {
            "admission_offers": [{"count": 2, "outcome": "deadline-passed", "source": "organizer_invitation"}],
            "cancellations": 0,
            "checked_in": 0,
            "invitation_requests": {"accepted": 0, "pending": 0, "rejected": 0},
            "registrations": 0,
            "registrations_by_path": {
                "approval": 0,
                "direct": 0,
                "organizer_invitation": 0,
                "unknown": 0,
                "waitlist": 0
            },
            "waitlist": 0
        },
        "event": {
            "canceled": false,
            "is_paid": false,
            "published": false,
            "timezone": "UTC",
            "capacity": null,
            "ends_at": null,
            "published_at": null,
            "registration_ends_at": null,
            "registration_starts_at": null,
            "starts_at": 1_710_090_000
        },
        "markers": [{"kind": "event-start", "ts": 1_710_090_000}],
        "markers_announcements_omitted": 0,
        "surveys": {
            "surveys": [
                {"eligible_count": 4, "eligible_respondents_count": 1, "event_survey_id": "00000000-0000-0000-0000-000000000030", "responses_count": 2, "state": "scheduled", "title": "Feedback"}
            ],
            "total_eligible_count": 0,
            "total_eligible_respondents_count": 0
        },
        "traffic": {
            "attribution_consistent": true,
            "registrations_baseline": 0,
            "registrations_by_ticket_type_per_day": [
                {"kind": "unknown", "series": [["2024-03-10", 1]], "event_ticket_type_id": null, "order": null, "title": null}
            ],
            "registrations_running_total": [],
            "views_after_end": 0,
            "views_before_start": 0,
            "views_by_source_per_day": [
                {"kind": "other-sources", "series": [["2024-03-10", 1]], "source": null}
            ],
            "views_total": 0
        },
        "utm": {
            "by_campaign": {"not_specified": 0, "remainder_count": 0, "remainder_views": 0, "values": []},
            "by_medium": {"not_specified": 0, "remainder_count": 0, "remainder_views": 0, "values": []},
            "by_source": {"not_specified": 0, "remainder_count": 0, "remainder_views": 0, "values": []},
            "combinations": [],
            "combinations_remainder_views": 0,
            "combinations_total_count": 0,
            "tagged_views": 0
        },
        "range": null,
        "tickets": null
    });

    // Deserialize the payload
    let stats: EventAnalytics = serde_json::from_value(payload).unwrap();

    // Check the enum, timestamp and optional encodings
    assert_eq!(
        stats.enrollment.admission_offers[0].outcome,
        EventAdmissionOfferOutcome::DeadlinePassed
    );
    assert_eq!(stats.markers[0].kind, EventAnalyticsMarkerKind::EventStart);
    assert_eq!(
        stats.event.starts_at,
        Some(Utc.timestamp_opt(1_710_090_000, 0).unwrap())
    );
    assert_eq!(
        stats.traffic.registrations_by_ticket_type_per_day[0].kind,
        RegistrationSeriesKind::Unknown
    );
    assert_eq!(
        stats.traffic.views_by_source_per_day[0].kind,
        ViewsSeriesKind::OtherSources
    );
    assert_eq!(stats.surveys.surveys[0].state, EventSurveyState::Scheduled);
    assert_eq!(stats.surveys.total_eligible_count, 0);
    assert!(stats.range.is_none());
    assert!(stats.tickets.is_none());
}

#[test]
fn test_fill_rate_divides_registrations_by_capacity() {
    let stats = sample_event_analytics();

    assert_eq!(stats.fill_rate(), Some(0.4));
}

#[test]
fn test_fill_rate_is_none_without_capacity() {
    let mut stats = sample_event_analytics();
    stats.event.capacity = None;
    assert_eq!(stats.fill_rate(), None);

    stats.event.capacity = Some(0);
    assert_eq!(stats.fill_rate(), None);
}

#[test]
fn test_has_ended_at_compares_the_effective_end() {
    let stats = sample_event_analytics();

    assert!(!stats.has_ended_at(Utc.with_ymd_and_hms(2024, 3, 10, 18, 59, 59).unwrap()));
    assert!(stats.has_ended_at(Utc.with_ymd_and_hms(2024, 3, 10, 19, 0, 0).unwrap()));
}

#[test]
fn test_has_ended_at_falls_back_to_the_start() {
    let mut stats = sample_event_analytics();
    stats.event.ends_at = None;

    assert!(stats.has_ended_at(Utc.with_ymd_and_hms(2024, 3, 10, 17, 0, 0).unwrap()));
}

#[test]
fn test_has_ended_at_is_false_for_undated_events() {
    let mut stats = sample_event_analytics();
    stats.event.ends_at = None;
    stats.event.starts_at = None;

    assert!(!stats.has_ended_at(Utc.with_ymd_and_hms(2030, 1, 1, 0, 0, 0).unwrap()));
}

#[test]
fn test_reserved_counts_allocated_seats_without_purchase() {
    let mut ticket_type = sample_event_analytics().tickets.unwrap().ticket_types[0].clone();
    assert_eq!(ticket_type.reserved(), 1);

    ticket_type.allocated = 2;
    assert_eq!(ticket_type.reserved(), 0);
}

#[test]
fn test_response_rate_is_none_without_eligible_attendees() {
    let mut surveys = sample_event_analytics().surveys;
    surveys.total_eligible_count = 0;
    surveys.total_eligible_respondents_count = 0;

    assert_eq!(surveys.response_rate(), None);
}

#[test]
fn test_response_rate_weights_surveys_by_their_audience() {
    let mut surveys = sample_event_analytics().surveys;
    surveys.total_eligible_count = 4 + 40;
    surveys.total_eligible_respondents_count = 4 + 7;

    assert_eq!(surveys.response_rate(), Some(0.25));
}

#[test]
fn test_share_of_views_divides_views_by_all_page_views() {
    let stats = sample_event_analytics();

    assert_eq!(stats.share_of_views(4), Some(0.2));
}

#[test]
fn test_share_of_views_is_none_when_attribution_is_inconsistent() {
    let mut stats = sample_event_analytics();
    stats.traffic.attribution_consistent = false;

    assert_eq!(stats.share_of_views(4), None);
}

#[test]
fn test_share_of_views_is_none_without_views() {
    let mut stats = sample_event_analytics();
    stats.traffic.views_total = 0;

    assert_eq!(stats.share_of_views(4), None);
}

#[test]
fn test_survey_response_rate_divides_eligible_respondents_by_eligible_attendees() {
    let survey = &sample_event_analytics().surveys.surveys[0];

    assert_eq!(survey.response_rate(), Some(0.75));
}

#[test]
fn test_survey_response_rate_is_none_without_eligible_attendees() {
    let mut survey = sample_event_analytics().surveys.surveys[0].clone();
    survey.eligible_count = 0;
    survey.eligible_respondents_count = 0;

    assert_eq!(survey.response_rate(), None);
}

#[test]
fn test_traffic_has_registrations_activity_requires_a_non_zero_day() {
    let mut traffic = sample_event_analytics().traffic;
    assert!(traffic.has_registrations_activity());

    for series in &mut traffic.registrations_by_ticket_type_per_day {
        series.series.iter_mut().for_each(|(_, count)| *count = 0);
    }
    assert!(!traffic.has_registrations_activity());
}

#[test]
fn test_traffic_has_views_activity_requires_a_non_zero_day() {
    let mut traffic = sample_event_analytics().traffic;
    assert!(traffic.has_views_activity());

    for series in &mut traffic.views_by_source_per_day {
        series.series.iter_mut().for_each(|(_, count)| *count = 0);
    }
    assert!(!traffic.has_views_activity());
}

#[test]
fn test_untagged_views_is_none_when_attribution_is_inconsistent() {
    let mut stats = sample_event_analytics();
    stats.traffic.attribution_consistent = false;

    assert_eq!(stats.untagged_views(), None);
}

#[test]
fn test_untagged_views_subtracts_tagged_views() {
    let stats = sample_event_analytics();

    assert_eq!(stats.untagged_views(), Some(16));
}

#[test]
fn test_views_hidden_count_adds_views_outside_the_range() {
    let stats = sample_event_analytics();

    assert_eq!(stats.views_hidden_count(), 5);
}
