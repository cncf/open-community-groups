use chrono::{Duration, Utc};

use crate::types::{
    dashboard::group::event_analytics::{EventAdmissionOfferCount, EventAdmissionOfferOutcome},
    event::EventAdmissionOfferSource,
    tests::sample_event_analytics,
};

use super::*;

#[test]
fn test_admission_offer_sources_group_outcomes_by_source() {
    let mut page = sample_page();
    page.stats.enrollment.admission_offers = vec![
        EventAdmissionOfferCount {
            count: 2,
            outcome: EventAdmissionOfferOutcome::Completed,
            source: EventAdmissionOfferSource::Approval,
        },
        EventAdmissionOfferCount {
            count: 3,
            outcome: EventAdmissionOfferOutcome::Completed,
            source: EventAdmissionOfferSource::Waitlist,
        },
        EventAdmissionOfferCount {
            count: 1,
            outcome: EventAdmissionOfferOutcome::DeadlinePassed,
            source: EventAdmissionOfferSource::Waitlist,
        },
    ];

    assert_eq!(
        page.admission_offer_sources(),
        vec![
            AdmissionOfferSourceSummary {
                label: "Approved request",
                outcomes: "2 completed".to_string(),
                total: 2,
            },
            AdmissionOfferSourceSummary {
                label: "Waiting list",
                outcomes: "3 completed · 1 expired (deadline passed)".to_string(),
                total: 4,
            },
        ]
    );
}

#[test]
fn test_check_ins_summary_reports_bins_and_timezone() {
    let page = sample_page();

    assert_eq!(
        page.check_ins_summary(),
        "3 check-ins in 15-minute intervals, shown in the Europe/Madrid timezone."
    );
}

#[test]
fn test_fill_curve_summary_reports_baseline_and_last_total() {
    let page = sample_page();

    assert_eq!(
        page.fill_curve_summary(),
        "Registrations grew from 0 to 4, from 2024-03-08 to 2024-03-10 (UTC days)."
    );
}

#[test]
fn test_funnel_stages_include_check_ins_after_the_event() {
    let page = sample_page();

    assert_eq!(
        page.funnel_stages(),
        vec![("Page views", 20), ("Registrations", 4), ("Checked in", 3)]
    );
    assert_eq!(
        page.funnel_summary(),
        "Page views 20, Registrations 4, Checked in 3."
    );
}

#[test]
fn test_funnel_stages_skip_check_ins_before_the_event_ends() {
    let mut page = sample_page();
    page.stats.event.ends_at = Some(Utc::now() + Duration::days(1));

    assert_eq!(
        page.funnel_stages(),
        vec![("Page views", 20), ("Registrations", 4)]
    );
}

#[test]
fn test_invitation_request_helpers_count_requests_by_status() {
    let page = sample_page();

    assert_eq!(page.invitation_requests_total(), 1);
    assert_eq!(
        page.invitation_requests_summary(),
        "0 pending · 1 accepted · 0 rejected"
    );
}

#[test]
fn test_membership_window_label_is_none_without_window() {
    let mut page = sample_page();
    page.stats.audience.window_starts_at = None;

    assert_eq!(page.membership_window_label(), None);
}

#[test]
fn test_membership_window_label_marks_capped_bounds() {
    let mut page = sample_page();
    page.stats.audience.window_end_capped = true;
    page.stats.audience.window_end_inferred = false;
    page.stats.audience.window_start_inferred = false;

    assert_eq!(
        page.membership_window_label().as_deref(),
        Some(
            "Registration window: Mar 8, 2024 11:00 to Mar 10, 2024 20:00 (cut short), Europe/Madrid."
        )
    );
}

#[test]
fn test_membership_window_label_marks_inferred_bounds() {
    let page = sample_page();

    assert_eq!(
        page.membership_window_label().as_deref(),
        Some(
            "Registration window: Mar 8, 2024 11:00 (publication) to Mar 10, 2024 20:00 (no registration close), Europe/Madrid."
        )
    );
}

#[test]
fn test_offer_labels_describe_outcomes_and_sources() {
    let page = sample_page();

    assert_eq!(
        page.offer_outcome_label(&EventAdmissionOfferOutcome::DeadlinePassed),
        "expired (deadline passed)"
    );
    assert_eq!(
        page.offer_source_label(&EventAdmissionOfferSource::OrganizerInvitation),
        "Organizer invitation"
    );
}

#[test]
fn test_rate_labels_use_not_applicable_without_denominator() {
    let mut page = sample_page();
    page.stats.event.capacity = None;
    page.stats.traffic.views_total = 0;

    assert_eq!(page.check_in_rate_label(), "75%");
    assert_eq!(page.conversion_rate_label(), "-");
    assert_eq!(page.fill_rate_label(), "-");
}

#[test]
fn test_registration_paths_skip_empty_paths() {
    let page = sample_page();

    assert_eq!(
        page.registration_paths(),
        vec![("Direct", 3), ("Waiting list", 1)]
    );
    assert_eq!(
        page.registration_paths_summary(),
        "Registrations by path: Direct 3, Waiting list 1."
    );
}

#[test]
fn test_share_label_uses_all_page_views() {
    let page = sample_page();

    assert_eq!(page.share_label(&4), "20%");
}

#[test]
fn test_share_label_is_unavailable_when_attribution_is_inconsistent() {
    let mut page = sample_page();
    page.stats.traffic.attribution_consistent = false;

    assert_eq!(page.share_label(&4), "Unavailable");
}

#[test]
fn test_survey_helpers_describe_survey_responses() {
    let page = sample_page();
    let survey = &page.stats.surveys.surveys[0];

    assert_eq!(page.survey_rate_label(survey), "75%");
    assert_eq!(page.survey_response_width(survey), "75.0");
    assert_eq!(page.survey_responses_short_summary(survey), "3 / 4");
    assert_eq!(
        page.survey_responses_summary(survey),
        "3 of 4 eligible attendees responded"
    );
}

#[test]
fn test_survey_helpers_handle_surveys_without_eligible_attendees() {
    // Setup a survey answered only by attendees no longer eligible
    let page = sample_page();
    let mut survey = page.stats.surveys.surveys[0].clone();
    survey.eligible_count = 0;
    survey.eligible_respondents_count = 0;
    survey.responses_count = 2;

    // Check the rate is not applicable and the stored total is reported
    assert_eq!(page.survey_rate_label(&survey), "-");
    assert_eq!(page.survey_response_width(&survey), "0");
    assert_eq!(
        page.survey_responses_short_summary(&survey),
        "0 / 0 · 2 total"
    );
    assert_eq!(
        page.survey_responses_summary(&survey),
        "No eligible attendees · 2 responses in total"
    );
}

#[test]
fn test_survey_responses_short_summary_adds_the_stored_total_when_it_differs() {
    let page = sample_page();
    let mut survey = page.stats.surveys.surveys[0].clone();
    survey.eligible_count = 1_200;
    survey.eligible_respondents_count = 1_000;
    survey.responses_count = 1_005;

    assert_eq!(
        page.survey_responses_short_summary(&survey),
        "1,000 / 1,200 · 1,005 total"
    );
}

#[test]
fn test_survey_responses_summary_adds_the_stored_total_when_it_differs() {
    let page = sample_page();
    let mut survey = page.stats.surveys.surveys[0].clone();
    survey.eligible_count = 1_200;
    survey.eligible_respondents_count = 1_000;
    survey.responses_count = 1_005;

    assert_eq!(
        page.survey_responses_summary(&survey),
        "1,000 of 1,200 eligible attendees responded · 1,005 responses in total"
    );
}

#[test]
fn test_surveys_response_rate_helpers_describe_opened_surveys() {
    let page = sample_page();

    assert_eq!(page.surveys_response_rate_label(), "75%");
    assert_eq!(
        page.surveys_response_rate_description(),
        "3 of 4 eligible attendees, across open and closed surveys"
    );
}

#[test]
fn test_surveys_response_rate_helpers_without_opened_surveys() {
    let mut page = sample_page();
    page.stats.surveys.total_eligible_count = 0;
    page.stats.surveys.total_eligible_respondents_count = 0;

    assert_eq!(page.surveys_response_rate_label(), "-");
    assert_eq!(
        page.surveys_response_rate_description(),
        "No eligible attendees in open or closed surveys yet"
    );
}

#[test]
fn test_ticket_type_helpers_describe_seat_usage() {
    let page = sample_page();
    let ticket_type = &page.stats.tickets.as_ref().unwrap().ticket_types[0];

    assert_eq!(page.ticket_type_progress_value(ticket_type), 5);
    assert_eq!(page.ticket_type_reserved_width(ticket_type), "10.0");
    assert_eq!(page.ticket_type_sold_width(ticket_type), "40.0");
    assert_eq!(
        page.ticket_type_summary(ticket_type),
        "4 sold · 1 reserved · 5 remaining of 10"
    );
}

#[test]
fn test_ticket_type_progress_value_is_bounded_by_seats() {
    let page = sample_page();
    let mut ticket_type = page.stats.tickets.as_ref().unwrap().ticket_types[0].clone();
    ticket_type.allocated = 12;

    assert_eq!(page.ticket_type_progress_value(&ticket_type), 10);
    assert_eq!(page.ticket_type_sold_width(&ticket_type), "40.0");
}

#[test]
fn test_views_summary_reports_hidden_views() {
    let page = sample_page();

    assert_eq!(
        page.views_summary(),
        "15 page views, from 2024-03-08 to 2024-03-10 (UTC days). 5 views outside these days are not shown."
    );
}

// Helpers.

/// Builds an analytics page for the sample past paid event.
fn sample_page() -> Page {
    Page {
        event_id: Uuid::new_v4(),
        stats: sample_event_analytics(),
    }
}
