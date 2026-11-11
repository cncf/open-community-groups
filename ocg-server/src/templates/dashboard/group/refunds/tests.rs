use askama::Template;
use chrono::{TimeZone, Utc};
use uuid::Uuid;

use crate::{
    templates::dashboard::BadgeTone,
    test_util::{element_text_with, opening_tag_with},
    types::{
        dashboard::group::refunds::{
            FinancialRecoveryKind, GroupFinancialRecovery, GroupRefund, GroupRefundStatus,
            RefundsView,
        },
        pagination::NavigationLinks,
    },
};

use super::{ListPage, status_tone};

#[test]
fn test_list_page_pluralizes_recovery_attempts() {
    let cases = [(1, "(1 attempt)"), (2, "(2 attempts)")];

    for (attempt_count, expected_attempts) in cases {
        // Setup a recovery with the given number of attempts
        let recovery = sample_recovery(attempt_count);
        let tooltip = format!("id=\"financial-failure-{}\"", recovery.payment_job_id);

        // Render the list page
        let html = sample_page(vec![], vec![recovery]).render().unwrap();

        // Check the failure tooltip pluralizes the attempt count
        let failure = element_text_with(&html, &tooltip);
        assert!(
            failure.ends_with(expected_attempts),
            "{attempt_count} attempts: {failure}"
        );

        // Check the failure trigger names the operation
        assert!(
            html.contains(
                "aria-label=\"Needs retry: view last failure for Application-fee refund\""
            ),
            "{attempt_count} attempts"
        );
    }
}

#[test]
fn test_list_page_requires_review_note_only_for_rejections() {
    // Render the list page with a refund awaiting review
    let refund = sample_refund(1, GroupRefundStatus::NeedsReview);
    let html = sample_page(vec![refund], vec![]).render().unwrap();

    // Check the rejection note is required and described by its help text
    let reject_note = opening_tag_with(&html, r#"id="refund-review-note""#);
    assert!(reject_note.contains(" required"));
    assert!(reject_note.contains(r#"aria-describedby="refund-review-note-help""#));

    // Check the approval note stays optional
    let approve_note = opening_tag_with(&html, r#"id="refund-approve-review-note""#);
    assert!(!approve_note.contains("required"));
    assert!(!approve_note.contains("aria-describedby"));

    // Check each note is labeled for its purpose
    assert!(html.contains("Reason shown to attendee"));
    assert!(html.contains("Review note (optional)"));
}

#[test]
fn test_list_page_retries_refunds_by_payment_job() {
    // Setup a refund awaiting review and a retryable refund with a payment job
    let payment_job_id = Uuid::from_u128(500);
    let review = sample_refund(1, GroupRefundStatus::NeedsReview);
    let retryable = GroupRefund {
        payment_job_id: Some(payment_job_id),
        ..sample_refund(2, GroupRefundStatus::RetryableFailure)
    };
    let review_purchase_id = review.event_purchase_id;

    // Render the list page
    let html = sample_page(vec![review, retryable.clone()], vec![]).render().unwrap();

    // Check retry targets the payment job and rejection targets the purchase
    assert!(html.contains(&format!(
        "hx-put=\"/dashboard/group/payment-jobs/{payment_job_id}/retry\""
    )));
    assert!(html.contains(&format!(
        "data-refund-reject-url=\"/dashboard/group/refunds/{review_purchase_id}/reject\""
    )));

    // Render the retryable refund without a payment job
    let retryable = GroupRefund {
        payment_job_id: None,
        ..retryable
    };
    let html = sample_page(vec![retryable], vec![]).render().unwrap();

    // Check no retry action is offered
    assert!(!html.contains("/dashboard/group/payment-jobs/"));
    assert!(!html.contains("Retry refund"));
}

#[test]
fn test_list_page_shows_retry_count_only_on_retryable_refunds() {
    // Setup retryable and queued refunds with recorded attempts
    let retryable = GroupRefund {
        attempt_count: Some(3),
        ..sample_refund(1, GroupRefundStatus::RetryableFailure)
    };
    let queued = GroupRefund {
        attempt_count: Some(2),
        ..sample_refund(2, GroupRefundStatus::Queued)
    };

    // Render the list page
    let html = sample_page(vec![retryable, queued], vec![]).render().unwrap();

    // Check only the retryable refund shows its attempt count
    assert!(html.contains("Needs retry (3 attempts)"));
    assert!(!html.contains("(2 attempts)"));
}

#[test]
fn test_status_tone() {
    let cases = [
        (
            "awaiting checkout",
            GroupRefundStatus::AwaitingCheckout,
            BadgeTone::Neutral,
        ),
        (
            "needs review",
            GroupRefundStatus::NeedsReview,
            BadgeTone::Warning,
        ),
        (
            "processing",
            GroupRefundStatus::Processing,
            BadgeTone::Neutral,
        ),
        ("queued", GroupRefundStatus::Queued, BadgeTone::Neutral),
        (
            "recovery required",
            GroupRefundStatus::RecoveryRequired,
            BadgeTone::Danger,
        ),
        ("refunded", GroupRefundStatus::Refunded, BadgeTone::Neutral),
        ("rejected", GroupRefundStatus::Rejected, BadgeTone::Danger),
        (
            "retryable failure",
            GroupRefundStatus::RetryableFailure,
            BadgeTone::Danger,
        ),
    ];

    for (case, status, expected) in cases {
        assert_eq!(status_tone(&status), expected, "{case}");
    }
}

// Helpers.

/// Active refunds list page for a manager with the given rows.
fn sample_page(
    refunds: Vec<GroupRefund>,
    financial_recoveries: Vec<GroupFinancialRecovery>,
) -> ListPage {
    let total = refunds.len() + financial_recoveries.len();

    ListPage {
        can_manage_events: true,
        events: vec![],
        financial_recoveries,
        navigation_links: NavigationLinks::default(),
        refresh_url: "/dashboard/group/refunds?view=active".to_string(),
        refunds,
        total,
        view: RefundsView::Active,

        event_id: None,
        offset: None,
        ts_query: None,
    }
}

/// Exhausted application-fee refund with the given number of attempts.
fn sample_recovery(attempt_count: i32) -> GroupFinancialRecovery {
    GroupFinancialRecovery {
        amount_minor: 125,
        attempt_count,
        currency_code: "USD".to_string(),
        email: "alice@example.test".to_string(),
        event_name: "Test event".to_string(),
        failure_message: "Provider request failed".to_string(),
        kind: FinancialRecoveryKind::EventPurchaseApplicationFeeAdjustment,
        operation: "Application-fee refund".to_string(),
        payment_job_id: Uuid::from_u128(1_000 + u128::from(attempt_count.unsigned_abs())),
        username: "alice".to_string(),

        name: Some("Alice".to_string()),
    }
}

/// Provider refund for the purchase identified by `id` in the given status.
fn sample_refund(id: u128, status: GroupRefundStatus) -> GroupRefund {
    let timestamp = Utc.with_ymd_and_hms(2026, 5, 10, 9, 0, 0).unwrap();

    GroupRefund {
        amount_minor: 2500,
        created_at: timestamp,
        currency_code: "USD".to_string(),
        email: "alice@example.test".to_string(),
        event_id: Uuid::from_u128(100),
        event_name: "Test event".to_string(),
        event_purchase_id: Uuid::from_u128(id),
        status,
        ticket_title: "General admission".to_string(),
        updated_at: timestamp,
        user_id: Uuid::from_u128(200),
        username: "alice".to_string(),

        attempt_count: None,
        external: false,
        failure_message: None,
        kind: None,
        name: Some("Alice".to_string()),
        payment_job_id: None,
        photo_url: None,
        provider_refund_id: None,
        requested_reason: None,
        review_note: None,
    }
}
