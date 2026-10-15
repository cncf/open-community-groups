use chrono::{Duration, Utc};

use crate::types::{
    dashboard::group::event_analytics::{
        EventAdmissionOfferCount, EventAdmissionOfferOutcome, EventQuestionOptionCount,
    },
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
fn test_percent_label_formats_ratios() {
    assert_eq!(percent_label(None), "-");
    assert_eq!(percent_label(Some(0.004)), "0.4%");
    assert_eq!(percent_label(Some(0.05)), "5%");
    assert_eq!(percent_label(Some(0.123)), "12%");
    assert_eq!(percent_label(Some(2.0)), "200%");
}

#[test]
fn test_question_options_hide_options_beyond_the_visible_ones() {
    let mut page = sample_page();
    page.stats.audience.questions[0].options = (0..12)
        .map(|index| EventQuestionOptionCount {
            count: 1,
            label: format!("Option {index}"),
            option_id: Uuid::from_u128(100 + index),
        })
        .collect();
    let question = &page.stats.audience.questions[0];
    let options = page.question_options(question);

    assert_eq!(page.question_hidden_options_count(question), 2);
    assert!(
        options[..QUESTION_VISIBLE_OPTIONS]
            .iter()
            .all(|option| !option.hidden)
    );
    assert!(options[QUESTION_VISIBLE_OPTIONS..].iter().all(|option| option.hidden));
    assert_eq!(options[11].label, "Option 11");
}

#[test]
fn test_question_options_sort_by_selections_with_shares_of_respondents() {
    let mut page = sample_page();
    page.stats.audience.questions[0].kind = QuestionnaireQuestionKind::MultiSelect;
    page.stats.audience.questions[0].respondents = 4;
    page.stats.audience.questions[0].options = vec![
        EventQuestionOptionCount {
            count: 1,
            label: "Cloud".to_string(),
            option_id: Uuid::from_u128(21),
        },
        EventQuestionOptionCount {
            count: 3,
            label: "AI".to_string(),
            option_id: Uuid::from_u128(22),
        },
        EventQuestionOptionCount {
            count: 1,
            label: "Edge".to_string(),
            option_id: Uuid::from_u128(23),
        },
    ];
    let question = &page.stats.audience.questions[0];

    assert!(page.is_multi_select(question));
    assert_eq!(page.question_hidden_options_count(question), 0);
    assert_eq!(
        page.question_options(question),
        vec![
            QuestionOptionShare {
                count: 3,
                hidden: false,
                label: "AI".to_string(),
                share_label: "75%".to_string(),
                width: "75.0".to_string(),
            },
            QuestionOptionShare {
                count: 1,
                hidden: false,
                label: "Cloud".to_string(),
                share_label: "25%".to_string(),
                width: "25.0".to_string(),
            },
            QuestionOptionShare {
                count: 1,
                hidden: false,
                label: "Edge".to_string(),
                share_label: "25%".to_string(),
                width: "25.0".to_string(),
            },
        ]
    );
}

#[test]
fn test_question_options_use_zero_shares_without_respondents() {
    let mut page = sample_page();
    page.stats.audience.questions[0].options[0].count = 0;
    page.stats.audience.questions[0].respondents = 0;
    let question = &page.stats.audience.questions[0];
    let options = page.question_options(question);

    assert!(!page.is_multi_select(question));
    assert_eq!(options[0].share_label, "0%");
    assert_eq!(options[0].width, "0");
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
