use chrono::{Duration, Utc};

use crate::{
    test_util::{element_html_with, element_text_with, normalize_whitespace, opening_tag_with},
    types::{
        payments::{EventPurchaseChargeModel, EventRefundProgress, EventRefundRequestStatus},
        tests::{sample_attendee, sample_event_summary},
    },
};

use super::*;

#[test]
fn test_list_page_confirms_attendance_cancellation_by_charge_model() {
    // Setup one confirmed attendee per charge model
    let free = sample_attendee();
    let paid = Attendee {
        amount_minor: Some(2500),
        charge_model: Some(EventPurchaseChargeModel::DirectCharge),
        currency_code: Some("USD".to_string()),
        ..sample_attendee()
    };
    let external = Attendee {
        amount_minor: Some(2500),
        charge_model: Some(EventPurchaseChargeModel::External),
        currency_code: Some("USD".to_string()),
        ..sample_attendee()
    };
    let cases = [
        (
            "free",
            free,
            [
                r#"data-confirm-message="Are you sure you want to cancel this attendance?""#,
                r#"data-confirm-text="Yes""#,
                r#"data-success-message="Attendance canceled.""#,
                r#"data-error-message="Something went wrong canceling this attendance. Please try again later.""#,
            ],
            "Cancel attendance",
        ),
        (
            "paid",
            paid,
            [
                r#"data-confirm-message="Queue a full refund for this attendee? Their attendance will remain active until the refund is confirmed.""#,
                r#"data-confirm-text="Queue refund""#,
                r#"data-success-message="Refund queued. Attendance will be canceled after confirmation.""#,
                r#"data-error-message="Something went wrong queueing this refund. Please try again later.""#,
            ],
            "Cancel attendance and refund",
        ),
        (
            "external",
            external,
            [
                r#"data-confirm-message="Cancel this attendance and confirm the money was returned outside this platform?""#,
                r#"data-confirm-text="Confirm returned""#,
                r#"data-success-message="Attendance canceled. Confirm the money was returned outside this platform.""#,
                r#"data-error-message="Something went wrong canceling this attendance. Please try again later.""#,
            ],
            "Cancel attendance and refund",
        ),
    ];

    for (case, attendee, messages, label) in cases {
        // Render the attendee row
        let event = sample_event_summary(Uuid::new_v4());
        let event_id = event.event_id;
        let user_id = attendee.user.user_id;
        let html = sample_page(vec![attendee], event).render().unwrap();

        // Check the cancellation request, confirmation copy and label
        let needle = format!(r#"id="cancel-attendance-{user_id}""#);
        let button = opening_tag_with(&html, &needle);
        assert!(
            button.contains(&format!(
                r#"hx-delete="/dashboard/group/events/{event_id}/attendees/{user_id}/attendance""#
            )),
            "{case}: cancellation request"
        );
        assert!(
            button.contains(r#"hx-trigger="confirmed""#),
            "{case}: confirmation trigger"
        );
        for message in messages {
            assert!(button.contains(message), "{case}: {message}");
        }
        assert_eq!(element_text_with(&html, &needle), label, "{case}: label");
    }
}

#[test]
fn test_list_page_disables_badge_awards_for_canceled_events() {
    let canceled_title = r#"title="Canceled events cannot award badges.""#;
    let cases = [("canceled", true, true), ("current", false, false)];

    for (case, canceled, expects_title) in cases {
        // Render the header actions for the event state
        let event = EventSummary {
            canceled,
            ..sample_event_summary(Uuid::new_v4())
        };
        let html = sample_page(vec![sample_attendee()], event).render().unwrap();

        // Check the award button title
        let button = opening_tag_with(&html, r#"id="attendee-badge-actions-button""#);
        assert_eq!(button.contains(canceled_title), expects_title, "{case}");
    }
}

#[test]
fn test_list_page_disables_scanner_opener_by_event_state() {
    let cases = [
        ("current", sample_event_summary(Uuid::new_v4()), None),
        (
            "canceled",
            EventSummary {
                canceled: true,
                ..sample_event_summary(Uuid::new_v4())
            },
            Some("Canceled events cannot scan attendees."),
        ),
        (
            "unpublished",
            EventSummary {
                published: false,
                ..sample_event_summary(Uuid::new_v4())
            },
            Some("Publish this event before scanning attendees."),
        ),
        (
            "past",
            past_event(),
            Some("Past events cannot scan attendees."),
        ),
    ];

    for (case, event, disabled_title) in cases {
        // Render the scanner opener for the event state
        let html = sample_page(vec![sample_attendee()], event).render().unwrap();

        // Check the opener is enabled or disabled with its reason
        let opener = opening_tag_with(&html, "data-group-check-in-open");
        match disabled_title {
            Some(disabled_title) => assert!(
                opener.contains(&format!(r#"disabled title="{disabled_title}""#)),
                "{case}: disabled title"
            ),
            None => assert!(!opener.contains("title="), "{case}: no disabled title"),
        }
    }
}

#[test]
fn test_list_page_escapes_attendee_profile_payload() {
    // Setup an attendee whose name needs escaping
    let mut attendee = sample_attendee();
    attendee.user.name = Some("O'Brien <x>".to_string());

    // Render the attendee row
    let html = sample_page(vec![attendee], sample_event_summary(Uuid::new_v4()))
        .render()
        .unwrap();

    // Check the profile payload stays inside its single-quoted attribute
    let trigger = opening_tag_with(&html, "data-user-profile-modal");
    let payload = trigger
        .split_once("data-user-profile='")
        .and_then(|(_, rest)| rest.split_once('\''))
        .map(|(payload, _)| payload)
        .expect("data-user-profile attribute");
    assert!(
        payload.contains("&#34;name&#34;:&#34;O\\u0027Brien \\u003cx\\u003e&#34;"),
        "payload escapes the name: {payload}"
    );
    assert!(!payload.contains("<x>"), "payload has no raw markup");

    // Check the accessible name escapes the attendee name
    assert!(
        trigger.contains(r#"aria-label="View profile for O&#39;Brien &#60;x&#62;""#),
        "accessible name escapes the name: {trigger}"
    );
}

#[test]
fn test_list_page_explains_disabled_attendance_cancellation() {
    let cases = [
        (
            "refund in progress",
            Attendee {
                refund_progress: Some(EventRefundProgress::Queued),
                ..sample_attendee()
            },
            sample_event_summary(Uuid::new_v4()),
            "A refund is already in progress for this attendee.",
        ),
        (
            "approved refund request",
            Attendee {
                refund_request_status: Some(EventRefundRequestStatus::Approved),
                ..sample_attendee()
            },
            sample_event_summary(Uuid::new_v4()),
            "This attendee's refund has already been approved.",
        ),
        (
            "canceled event",
            sample_attendee(),
            EventSummary {
                canceled: true,
                ..sample_event_summary(Uuid::new_v4())
            },
            "Canceled event attendance cannot be canceled.",
        ),
        (
            "past event",
            sample_attendee(),
            past_event(),
            "Past event attendance cannot be canceled.",
        ),
    ];

    for (case, attendee, event, title) in cases {
        // Render the attendee row
        let user_id = attendee.user.user_id;
        let html = sample_page(vec![attendee], event).render().unwrap();

        // Check the cancellation is disabled with its reason
        let button = opening_tag_with(&html, &format!(r#"id="cancel-attendance-{user_id}""#));
        assert!(
            normalize_whitespace(button).contains(&format!(r#" disabled title="{title}""#)),
            "{case}: disabled title"
        );
        assert!(!button.contains("hx-delete"), "{case}: no request");
    }
}

#[test]
fn test_list_page_explains_unavailable_check_in_toggle() {
    // Setup the toggle states and their accessible names
    let unchecked = |enrollment_status| Attendee {
        checked_in: false,
        checked_in_at: None,
        enrollment_status,
        ..sample_attendee()
    };
    let mut cases = vec![(
        "confirmed and manageable",
        sample_page(
            vec![unchecked(AttendeeEnrollmentStatus::Confirmed)],
            sample_event_summary(Uuid::new_v4()),
        ),
        "Check in attendee",
    )];
    for (case, status, label) in [
        (
            "attendance canceled",
            AttendeeEnrollmentStatus::AttendanceCanceled,
            "Canceled attendance cannot be checked in",
        ),
        (
            "checkout pending",
            AttendeeEnrollmentStatus::CheckoutPending,
            "Pending checkout cannot be checked in",
        ),
        (
            "invitation canceled",
            AttendeeEnrollmentStatus::InvitationCanceled,
            "Canceled invitation cannot be checked in",
        ),
        (
            "invitation declined",
            AttendeeEnrollmentStatus::InvitationDeclined,
            "Declined invitation cannot be checked in",
        ),
        (
            "invitation expired",
            AttendeeEnrollmentStatus::InvitationExpired,
            "Expired invitation cannot be checked in",
        ),
        (
            "invitation pending",
            AttendeeEnrollmentStatus::InvitationPending,
            "Pending invitation cannot be checked in",
        ),
        (
            "registration pending",
            AttendeeEnrollmentStatus::RegistrationPending,
            "Pending registration cannot be checked in",
        ),
        (
            "payment pending",
            AttendeeEnrollmentStatus::PaymentPending,
            "Pending payment cannot be checked in",
        ),
    ] {
        cases.push((
            case,
            sample_page(
                vec![unchecked(status)],
                sample_event_summary(Uuid::new_v4()),
            ),
            label,
        ));
    }
    let mut no_check_in_role = sample_page(
        vec![unchecked(AttendeeEnrollmentStatus::Confirmed)],
        sample_event_summary(Uuid::new_v4()),
    );
    no_check_in_role.can_manage_check_ins = false;
    cases.push((
        "role cannot manage check-in",
        no_check_in_role,
        "Your role cannot manage check-in",
    ));
    cases.push((
        "canceled event",
        sample_page(
            vec![unchecked(AttendeeEnrollmentStatus::Confirmed)],
            EventSummary {
                canceled: true,
                ..sample_event_summary(Uuid::new_v4())
            },
        ),
        "Canceled event check-in unavailable",
    ));

    for (case, page, label) in cases {
        // Render the attendee row
        let html = page.render().unwrap();

        // Check the toggle's accessible name and availability
        let toggle = opening_tag_with(&html, "check-in-toggle");
        assert!(
            toggle.contains(&format!(r#"aria-label=" {label} ""#)),
            "{case}: accessible name"
        );
        assert_eq!(
            toggle.contains("disabled"),
            label != "Check in attendee",
            "{case}: disabled"
        );
    }
}

#[test]
fn test_list_page_gives_each_status_tooltip_instance_a_unique_id() {
    // Setup an attendee waiting for external payment confirmation
    let attendee = Attendee {
        amount_minor: Some(2500),
        charge_model: Some(EventPurchaseChargeModel::External),
        checked_in: false,
        checked_in_at: None,
        currency_code: Some("USD".to_string()),
        enrollment_status: AttendeeEnrollmentStatus::PaymentPending,
        event_purchase_id: Some(Uuid::new_v4()),
        external_payment_deadline: Some(Utc::now() + Duration::days(2)),
        external_payment_reference: Some(Uuid::new_v4()),
        ticket_title: Some("General admission".to_string()),
        ..sample_attendee()
    };
    let user_id = attendee.user.user_id;

    // Render the attendee row
    let html = sample_page(vec![attendee], sample_event_summary(Uuid::new_v4()))
        .render()
        .unwrap();

    // Check each status instance owns one referenced tooltip
    for instance in ["mobile", "ticket", "desktop"] {
        let tooltip_id = format!("attendee-external-payment-details-{user_id}-{instance}");
        assert_eq!(
            html.matches(&format!(r#"id="{tooltip_id}""#)).count(),
            1,
            "{instance}: tooltip id is unique"
        );
        assert_eq!(
            html.matches(&format!(r#"aria-describedby="{tooltip_id}""#)).count(),
            1,
            "{instance}: tooltip is referenced"
        );
    }
}

#[test]
fn test_list_page_offers_mark_paid_only_for_pending_external_purchases() {
    // Setup a pending external payment with and without a purchase
    let event_purchase_id = Uuid::new_v4();
    let pending = Attendee {
        amount_minor: Some(2500),
        charge_model: Some(EventPurchaseChargeModel::External),
        checked_in: false,
        checked_in_at: None,
        currency_code: Some("USD".to_string()),
        enrollment_status: AttendeeEnrollmentStatus::PaymentPending,
        event_purchase_id: Some(event_purchase_id),
        ..sample_attendee()
    };
    let without_purchase = Attendee {
        event_purchase_id: None,
        ..pending.clone()
    };
    let cases = [
        (
            "pending purchase",
            pending.clone(),
            sample_event_summary(Uuid::new_v4()),
            true,
        ),
        (
            "canceled event",
            pending,
            EventSummary {
                canceled: true,
                ..sample_event_summary(Uuid::new_v4())
            },
            false,
        ),
        (
            "no purchase",
            without_purchase,
            sample_event_summary(Uuid::new_v4()),
            false,
        ),
    ];

    for (case, attendee, event, offered) in cases {
        // Render the attendee row
        let event_id = event.event_id;
        let html = sample_page(vec![attendee], event).render().unwrap();

        // Check the mark-paid action and its endpoint
        let url = format!(
            r#"data-external-payment-url="/dashboard/group/events/{event_id}/purchases/{event_purchase_id}/external-payment""#
        );
        assert_eq!(html.contains(&url), offered, "{case}: mark-paid endpoint");
        assert_eq!(
            html.contains("data-external-payment-url="),
            offered,
            "{case}: mark-paid action"
        );
    }
}

#[test]
fn test_list_page_offers_refund_retry_only_to_event_managers() {
    // Setup an attendee whose refund needs a retry
    let refund_payment_job_id = Uuid::new_v4();
    let attendee = Attendee {
        amount_minor: Some(2500),
        charge_model: Some(EventPurchaseChargeModel::DirectCharge),
        currency_code: Some("USD".to_string()),
        event_purchase_id: Some(Uuid::new_v4()),
        refund_payment_job_id: Some(refund_payment_job_id),
        refund_progress: Some(EventRefundProgress::RetryableFailure),
        ..sample_attendee()
    };
    let user_id = attendee.user.user_id;
    let retry_id = format!(r#"id="retry-refund-{user_id}""#);

    // Check event managers can retry the refund job
    let html = sample_page(vec![attendee.clone()], sample_event_summary(Uuid::new_v4()))
        .render()
        .unwrap();
    let button = opening_tag_with(&html, &retry_id);
    assert!(
        button.contains(&format!(
            r#"hx-put="/dashboard/group/payment-jobs/{refund_payment_job_id}/retry""#
        )),
        "event manager: retry request"
    );

    // Check other roles cannot retry the refund job
    let mut page = sample_page(vec![attendee], sample_event_summary(Uuid::new_v4()));
    page.can_manage_events = false;
    let html = page.render().unwrap();
    assert!(!html.contains(&retry_id), "other role: no retry action");
}

#[test]
fn test_list_page_preserves_active_filters_in_its_forms() {
    // Setup a page with every preserved filter active
    let event_ticket_type_id = Uuid::new_v4();
    let mut page = sample_page(
        vec![sample_attendee()],
        sample_event_summary(Uuid::new_v4()),
    );
    page.checked_in = Some(true);
    page.event_ticket_type_ids = Some(vec![event_ticket_type_id]);
    page.sort = Some(AttendeesSort::NameDesc);
    page.title = Some(PresenceFilter::Present);
    page.ts_query = Some("ana".to_string());

    // Render the page
    let html = page.render().unwrap();
    let normalized_html = normalize_whitespace(&html);

    // Check the forms carry the active filters as hidden inputs
    for (name, value) in [
        ("checked_in", "true".to_string()),
        ("sort", "name-desc".to_string()),
        ("title", "present".to_string()),
        ("ts_query", "ana".to_string()),
        ("event_ticket_type_ids[]", event_ticket_type_id.to_string()),
    ] {
        let input = format!(r#"<input type="hidden" name="{name}" value="{value}">"#);
        assert!(normalized_html.contains(&input), "{name}: {input}");
    }

    // Check the active filter chips sit in the group named by its label
    let group_needle = r#"aria-labelledby="attendees-active-filters-label""#;
    assert!(opening_tag_with(&html, group_needle).contains(r#"role="group""#));
    assert_eq!(
        element_text_with(&html, r#"id="attendees-active-filters-label""#),
        "Active filters"
    );
    let active_filters = element_text_with(&html, group_needle);
    assert!(
        active_filters.contains("Checked In: Yes"),
        "{active_filters}"
    );
    assert!(
        active_filters.contains("Position: Present"),
        "{active_filters}"
    );
}

#[test]
fn test_list_page_renders_status_badge_by_precedence() {
    let mut cases = vec![
        ("confirmed", sample_attendee(), "Active"),
        (
            "paid manually invited confirmed",
            Attendee {
                amount_minor: Some(2500),
                currency_code: Some("USD".to_string()),
                manually_invited: true,
                ..sample_attendee()
            },
            "Ticket claimed",
        ),
        (
            "free manually invited confirmed",
            Attendee {
                manually_invited: true,
                ..sample_attendee()
            },
            "Invited",
        ),
        (
            "refund request rejected",
            Attendee {
                refund_request_status: Some(EventRefundRequestStatus::Rejected),
                ..sample_attendee()
            },
            "Refund rejected",
        ),
        (
            "checkout pending",
            Attendee {
                checked_in: false,
                checked_in_at: None,
                enrollment_status: AttendeeEnrollmentStatus::CheckoutPending,
                ..sample_attendee()
            },
            "Checkout pending",
        ),
    ];
    for (case, refund_progress, label) in [
        (
            "refund awaiting checkout",
            EventRefundProgress::AwaitingCheckout,
            "Waiting for checkout",
        ),
        (
            "refund queued",
            EventRefundProgress::Queued,
            "Refund queued",
        ),
        (
            "refund processing",
            EventRefundProgress::Processing,
            "Refund processing",
        ),
        (
            "refund retryable failure",
            EventRefundProgress::RetryableFailure,
            "Refund needs retry",
        ),
        (
            "refund recovery required",
            EventRefundProgress::RecoveryRequired,
            "Recovery required",
        ),
        ("refunded", EventRefundProgress::Refunded, "Refunded"),
    ] {
        cases.push((
            case,
            Attendee {
                refund_progress: Some(refund_progress),
                ..sample_attendee()
            },
            label,
        ));
    }

    for (case, attendee, label) in cases {
        // Render the attendee row
        let html = sample_page(vec![attendee], sample_event_summary(Uuid::new_v4()))
            .render()
            .unwrap();

        // Check the winning badge and that the confirmed fallback yields to it
        assert!(html.contains(&format!(">{label}<")), "{case}: {label}");
        if label != "Active" {
            assert!(!html.contains(">Active<"), "{case}: no Active fallback");
        }
    }
}

#[test]
fn test_list_page_scanner_opener_carries_event_timezone() {
    // Render the scanner opener for a UTC event
    let html = sample_page(
        vec![sample_attendee()],
        sample_event_summary(Uuid::new_v4()),
    )
    .render()
    .unwrap();

    // Check the opener passes the event timezone to the scanner
    let opener = opening_tag_with(&html, "data-group-check-in-open");
    assert!(opener.contains(r#"data-event-timezone="UTC""#));
}

#[test]
fn test_list_page_selects_the_current_enrollment_status_filter() {
    for status in all_filters() {
        // Render the page with the status filter
        let mut page = sample_page(
            vec![sample_attendee()],
            sample_event_summary(Uuid::new_v4()),
        );
        page.status = status;
        let html = page.render().unwrap();
        let select = element_html_with(&html, r#"id="attendees-enrollment-status""#);

        // Check only the matching option is selected
        let option = opening_tag_with(select, &format!(r#"value="{status}""#));
        assert!(option.contains("selected"), "{status}: selected");
        let other = if status == AttendeeEnrollmentStatusFilter::Current {
            AttendeeEnrollmentStatusFilter::All
        } else {
            AttendeeEnrollmentStatusFilter::Current
        };
        let other_option = opening_tag_with(select, &format!(r#"value="{other}""#));
        assert!(
            !other_option.contains("selected"),
            "{status}: {other} not selected"
        );
    }
}

// Helpers.

/// Returns every enrollment status filter, failing to compile when a variant
/// is added without a case here.
fn all_filters() -> Vec<AttendeeEnrollmentStatusFilter> {
    use AttendeeEnrollmentStatusFilter as Filter;

    let filters = vec![
        Filter::All,
        Filter::AttendanceCanceled,
        Filter::CheckoutPending,
        Filter::Confirmed,
        Filter::Current,
        Filter::History,
        Filter::InvitationCanceled,
        Filter::InvitationDeclined,
        Filter::InvitationExpired,
        Filter::InvitationPending,
        Filter::PaymentPending,
        Filter::RegistrationPending,
    ];
    for filter in &filters {
        match filter {
            Filter::All
            | Filter::AttendanceCanceled
            | Filter::CheckoutPending
            | Filter::Confirmed
            | Filter::Current
            | Filter::History
            | Filter::InvitationCanceled
            | Filter::InvitationDeclined
            | Filter::InvitationExpired
            | Filter::InvitationPending
            | Filter::PaymentPending
            | Filter::RegistrationPending => {}
        }
    }
    filters
}

/// Builds a published event that ended an hour ago.
fn past_event() -> EventSummary {
    let starts_at = Utc::now() - Duration::hours(3);
    EventSummary {
        ends_at: Some(starts_at + Duration::hours(2)),
        starts_at: Some(starts_at),
        ..sample_event_summary(Uuid::new_v4())
    }
}

/// Builds an unfiltered current-enrollments page for a manager who can
/// process check-ins and manage events.
fn sample_page(attendees: Vec<Attendee>, event: EventSummary) -> ListPage {
    let refresh_url = format!("/dashboard/group/events/{}/attendees", event.event_id);
    let total = attendees.len();

    ListPage {
        all_attendees_email_recipient_total: total,
        attendees,
        can_manage_check_ins: true,
        can_manage_events: true,
        event,
        navigation_links: pagination::NavigationLinks::default(),
        refresh_url,
        status: AttendeeEnrollmentStatusFilter::Current,
        total,

        checked_in: None,
        event_ticket_type_ids: None,
        limit: None,
        offset: None,
        registration_questions: vec![],
        sort: None,
        title: None,
        ts_query: None,
    }
}
