use askama::Template;
use chrono::{TimeZone, Utc};
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, element_text_with, opening_tag_with},
    types::{
        dashboard::group::invitation_requests::{
            InvitationRequest, InvitationRequestsStatusFilter,
        },
        event::{EventAdmissionOfferStatus, EventSummary},
        pagination::NavigationLinks,
        payments::{EventTicketCurrentPrice, EventTicketType, EventTicketTypeAvailability},
        tests::{sample_event_summary, sample_invitation_request},
    },
};

use super::ListPage;

#[test]
fn test_list_page_labels_active_filters_group() {
    // Render the page with an active status filter
    let mut page = sample_page(vec![sample_invitation_request()], sample_event(vec![]));
    page.status = InvitationRequestsStatusFilter::Pending;
    let html = page.render().unwrap();

    // Check the active filter chips sit in the group named by its label
    let group_needle = r#"aria-labelledby="invitation-requests-active-filters-label""#;
    assert!(opening_tag_with(&html, group_needle).contains(r#"role="group""#));
    assert_eq!(
        element_text_with(&html, r#"id="invitation-requests-active-filters-label""#),
        "Active filters"
    );
    let active_filters = element_text_with(&html, group_needle);
    assert!(
        active_filters.contains("Status: Pending"),
        "{active_filters}"
    );
}

#[test]
fn test_list_page_labels_offer_by_status() {
    let cases = [
        (EventAdmissionOfferStatus::Pending, "Offer pending"),
        (
            EventAdmissionOfferStatus::CheckoutPending,
            "Checkout pending",
        ),
        (EventAdmissionOfferStatus::Completed, "Ticket claimed"),
        (EventAdmissionOfferStatus::Expired, "Offer expired"),
        (EventAdmissionOfferStatus::Canceled, "Offer canceled"),
        (EventAdmissionOfferStatus::Declined, "Offer declined"),
    ];

    for (status, expected_label) in cases {
        // Setup a request with an offer in the given status
        let request = InvitationRequest {
            admission_offer_id: Some(Uuid::from_u128(10)),
            admission_offer_status: Some(status),
            offer_expires_at: Some(Utc.with_ymd_and_hms(2099, 5, 10, 9, 0, 0).unwrap()),
            offered_ticket_title: Some("General admission".to_string()),
            ..sample_invitation_request()
        };
        let user_id = request.user.user_id;

        // Render the list page
        let html = sample_page(vec![request], sample_event_summary(Uuid::from_u128(1)))
            .render()
            .unwrap();

        // Check the offer badge names the status and links its details
        let trigger = format!("aria-describedby=\"invitation-request-offer-details-{user_id}\"");
        assert_eq!(
            element_text_with(&html, &trigger),
            expected_label,
            "{status}"
        );
        assert!(
            html.contains(&format!(
                "id=\"invitation-request-offer-details-{user_id}\""
            )),
            "{status}"
        );
    }
}

#[test]
fn test_list_page_offers_only_assignable_invitation_only_ticket_types() {
    // Setup ticket types covering each assignability rule
    let assignable_id = Uuid::from_u128(1);
    let public_id = Uuid::from_u128(2);
    let sold_out_id = Uuid::from_u128(3);
    let unpriced_id = Uuid::from_u128(4);
    let assignable = sample_ticket_type(assignable_id, "Speaker pass");
    let public = EventTicketType {
        availability: EventTicketTypeAvailability::Public,
        ..sample_ticket_type(public_id, "General admission")
    };
    let sold_out = EventTicketType {
        sold_out: true,
        ..sample_ticket_type(sold_out_id, "Sponsor pass")
    };
    let unpriced = EventTicketType {
        current_price: None,
        ..sample_ticket_type(unpriced_id, "Volunteer pass")
    };

    // Setup a pending request without a requested ticket type
    let request = InvitationRequest {
        requested_event_ticket_type_id: None,
        requested_ticket_title: None,
        ..sample_invitation_request()
    };
    let user_id = request.user.user_id;
    let select = format!("id=\"invitation-request-ticket-type-{user_id}\"");

    // Render the page with every ticket type
    let event = sample_event(vec![assignable, public, sold_out.clone(), unpriced.clone()]);
    let html = sample_page(vec![request.clone()], event).render().unwrap();

    // Check only the assignable ticket type is offered
    let options = element_html_with(&html, &select);
    assert!(options.contains(&format!("value=\"{assignable_id}\"")));
    assert!(!options.contains(&format!("value=\"{public_id}\"")));
    assert!(!options.contains(&format!("value=\"{sold_out_id}\"")));
    assert!(!options.contains(&format!("value=\"{unpriced_id}\"")));

    // Render the page without assignable ticket types
    let event = sample_event(vec![sold_out, unpriced]);
    let html = sample_page(vec![request], event).render().unwrap();

    // Check only the placeholder option remains and the empty state is available
    let options = element_html_with(&html, &select);
    assert_eq!(options.matches("<option").count(), 1);
    assert!(options.contains("<option value=\"\">Select ticket type</option>"));
    assert!(
        element_text_with(&html, "data-invitation-request-ticket-empty")
            .starts_with("No invitation-only ticket types can be assigned.")
    );
}

// Helpers.

/// Upcoming event that requires invitation approval with the given ticket types.
fn sample_event(ticket_types: Vec<EventTicketType>) -> EventSummary {
    EventSummary {
        attendee_approval_required: true,
        payment_currency_code: Some("USD".to_string()),
        ticket_types: Some(ticket_types),
        ..sample_event_summary(Uuid::from_u128(100))
    }
}

/// Invitation requests list page showing all statuses for a manager.
fn sample_page(invitation_requests: Vec<InvitationRequest>, event: EventSummary) -> ListPage {
    let total = invitation_requests.len();

    ListPage {
        can_manage_events: true,
        event,
        invitation_requests,
        navigation_links: NavigationLinks::default(),
        refresh_url: "/dashboard/group/events/invitation-requests?status=all".to_string(),
        status: InvitationRequestsStatusFilter::All,
        total,

        limit: None,
        offset: None,
        registration_questions: vec![],
        sort: None,
        title: None,
        ts_query: None,
    }
}

/// Active, priced, invitation-only ticket type with available seats.
fn sample_ticket_type(event_ticket_type_id: Uuid, title: &str) -> EventTicketType {
    EventTicketType {
        active: true,
        availability: EventTicketTypeAvailability::InvitationOnly,
        event_ticket_type_id,
        order: 1,
        title: title.to_string(),

        current_price: Some(EventTicketCurrentPrice {
            amount_minor: 2500,
            ..Default::default()
        }),
        ..Default::default()
    }
}
