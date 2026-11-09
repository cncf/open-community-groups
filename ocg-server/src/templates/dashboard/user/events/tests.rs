use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::New_York;
use uuid::Uuid;

use crate::{
    test_util::opening_tag_with,
    types::{
        dashboard::user::events::{UserEvent, UserEventRole},
        event::EventEnrollmentStatus,
        pagination::NavigationLinks,
        payments::{EventRefundRequestStatus, ExternalPaymentInfo},
        tests::sample_user_event,
    },
};

use super::ListPage;

#[test]
fn test_list_page_disables_cancel_attendance_when_unavailable() {
    // Render a paid attendance, which My Events cannot cancel
    let event_id = Uuid::from_u128(1);
    let event = UserEvent {
        has_paid_purchase: true,
        ..sample_user_event(event_id)
    };
    assert!(!event.can_cancel_attendance());
    let html = sample_page(vec![event]).render().unwrap();

    // Check the cancel action stays visible but disabled with an explanation
    let button = opening_tag_with(&html, &format!(r#"id="cancel-attendance-{event_id}""#));
    assert!(button.contains("disabled"));
    assert!(button.contains(r#"title="This attendance cannot be canceled from My Events.""#));
    assert!(!html.contains(r#"/attendance""#));
}

#[test]
fn test_list_page_labels_refund_request_status() {
    let cases = [
        (EventRefundRequestStatus::Pending, "Refund requested"),
        (EventRefundRequestStatus::Approving, "Refund processing"),
        (EventRefundRequestStatus::Approved, "Refund approved"),
        (EventRefundRequestStatus::Rejected, "Refund rejected"),
    ];

    for (status, label) in cases {
        // Render an event with the refund request status
        let event = UserEvent {
            refund_request_status: Some(status),
            ..sample_user_event(Uuid::from_u128(1))
        };
        let html = sample_page(vec![event]).render().unwrap();

        // Check the status badge label
        assert!(html.contains(label), "{status:?} should render {label:?}");
    }
}

#[test]
fn test_list_page_offers_checkout_recovery_for_active_checkout() {
    // Render an active checkout without a provider resume URL
    let event_id = Uuid::from_u128(1);
    let event = UserEvent {
        enrollment_status: Some(EventEnrollmentStatus::PendingPayment),
        ..sample_user_event(event_id)
    };
    assert!(event.can_cancel_checkout());
    let html = sample_page(vec![event]).render().unwrap();

    // Check the menu resumes checkout on the public event page, linked next
    // to the title link
    assert!(html.contains("Continue to checkout"));
    let event_page_href = r#"href="/test-community/group/def5678/event/ghi9abc""#;
    assert_eq!(html.matches(event_page_href).count(), 2);

    // Check the menu cancels the checkout through the event checkout endpoint
    let cancel_button = opening_tag_with(&html, &format!(r#"id="cancel-checkout-{event_id}""#));
    assert!(cancel_button.contains(&format!(
        r#"hx-delete="/test-community/event/{event_id}/checkout""#
    )));
}

#[test]
fn test_list_page_renders_external_payment_details() {
    // Render a pending external payment in a timezone with daylight saving time
    let reference = Uuid::from_u128(0x0123);
    let url = "https://payments.example.test/ocg";
    let mut event = UserEvent {
        external_payment: Some(ExternalPaymentInfo {
            amount_minor: 2500,
            currency_code: "USD".to_string(),
            deadline: Utc.with_ymd_and_hms(2030, 6, 15, 18, 0, 0).unwrap(),
            reference,
            url: url.to_string(),

            instructions: Some("Pay <b>now</b>".to_string()),
        }),
        ..sample_user_event(Uuid::from_u128(1))
    };
    event.event.timezone = New_York;
    let html = sample_page(vec![event]).render().unwrap();

    // Check the status badge tooltip details and instruction escaping
    assert!(html.contains("Payment pending"));
    assert!(html.contains("Jun 15, 2030 at 2:00 PM EDT"));
    assert!(html.contains(&reference.to_string()));
    assert!(html.contains("Pay &#60;b&#62;now&#60;/b&#62;"));
    assert!(!html.contains("<b>now</b>"));

    // Check the payment page opens safely in a new tab
    let link = opening_tag_with(&html, &format!(r#"href="{url}""#));
    assert!(link.contains(r#"target="_blank""#));
    assert!(link.contains(r#"rel="noopener noreferrer""#));
    assert!(html.contains("Open payment page"));
}

#[test]
fn test_list_page_routes_active_offer_to_invitations() {
    // Render an active admission offer
    let admission_offer_id = Uuid::from_u128(0x0ff3);
    let event = UserEvent {
        admission_offer_id: Some(admission_offer_id),
        enrollment_status: None,
        roles: vec![UserEventRole::Offer],
        ..sample_user_event(Uuid::from_u128(1))
    };
    assert!(event.has_active_offer());
    let html = sample_page(vec![event]).render().unwrap();

    // Check the menu links to the offer in the invitations tab
    assert!(html.contains(&format!(
        r#"href="/dashboard/user?tab=invitations#event-offer-{admission_offer_id}""#
    )));
    assert!(html.contains("View event offer"));
}

// Helpers.

/// Builds a single-page events list with the given events.
fn sample_page(events: Vec<UserEvent>) -> ListPage {
    let total = events.len();
    ListPage {
        events,
        navigation_links: NavigationLinks::default(),
        total,

        offset: None,
    }
}
