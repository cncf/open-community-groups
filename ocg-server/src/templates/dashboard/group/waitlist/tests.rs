use askama::Template;
use chrono::Utc;
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, element_text_with, normalize_whitespace, opening_tag_with},
    types::{
        dashboard::group::{PresenceFilter, waitlist::WaitlistEntry},
        event::{EventAdmissionOfferStatus, EventSummary},
        pagination::NavigationLinks,
        payments::{EventTicketCurrentPrice, EventTicketType, EventTicketTypeAvailability},
        tests::sample_event_summary,
        user::User,
    },
};

use super::{ListPage, waitlist_row_key};

#[test]
fn test_list_page_labels_active_filters_group() {
    // Render the page with an active title filter
    let mut page = sample_page(
        vec![entry(Uuid::from_u128(1), None, None)],
        sample_event_summary(Uuid::from_u128(100)),
        1,
    );
    page.title = Some(PresenceFilter::Present);
    let html = page.render().unwrap();

    // Check the active filter chips sit in the group named by its label
    let group_needle = r#"aria-labelledby="waitlist-active-filters-label""#;
    assert!(opening_tag_with(&html, group_needle).contains(r#"role="group""#));
    assert_eq!(
        element_text_with(&html, r#"id="waitlist-active-filters-label""#),
        "Active filters"
    );
    let active_filters = element_text_with(&html, group_needle);
    assert!(
        active_filters.contains("Position: Present"),
        "{active_filters}"
    );
}

#[test]
fn test_list_page_offers_only_assignable_ticket_types_for_invites() {
    // Setup ticket types covering each assignability rule
    let public_id = Uuid::from_u128(1);
    let invitation_only_id = Uuid::from_u128(2);
    let sold_out_id = Uuid::from_u128(3);
    let inactive_id = Uuid::from_u128(4);
    let unpriced_id = Uuid::from_u128(5);
    let public = sample_ticket_type(public_id, "General admission");
    let invitation_only = EventTicketType {
        availability: EventTicketTypeAvailability::InvitationOnly,
        ..sample_ticket_type(invitation_only_id, "Speaker pass")
    };
    let sold_out = EventTicketType {
        sold_out: true,
        ..sample_ticket_type(sold_out_id, "Sponsor pass")
    };
    let inactive = EventTicketType {
        active: false,
        ..sample_ticket_type(inactive_id, "Early bird")
    };
    let unpriced = EventTicketType {
        current_price: None,
        ..sample_ticket_type(unpriced_id, "Volunteer pass")
    };

    // Setup a queued entry waiting for the public ticket type
    let queued = WaitlistEntry {
        event_ticket_type_id: public_id,
        ..entry(Uuid::from_u128(10), None, None)
    };
    let select = "data-waitlist-invite-ticket-type";

    // Render the page with every ticket type
    let event = sample_event(vec![
        public,
        invitation_only,
        sold_out.clone(),
        inactive.clone(),
        unpriced.clone(),
    ]);
    let html = sample_page(vec![queued.clone()], event, 1).render().unwrap();

    // Check the entry's ticket type is preselected and labeled public
    let public_option = format!("value=\"{public_id}\"");
    assert!(opening_tag_with(&html, &public_option).contains("selected"));
    assert_eq!(
        element_text_with(&html, &public_option),
        "General admission (Public)"
    );

    // Check the invitation-only ticket type is labeled as such
    assert_eq!(
        element_text_with(&html, &format!("value=\"{invitation_only_id}\"")),
        "Speaker pass (Invitation only)"
    );

    // Check unassignable ticket types are not offered
    let options = element_html_with(&html, select);
    assert!(!options.contains(&format!("value=\"{sold_out_id}\"")));
    assert!(!options.contains(&format!("value=\"{inactive_id}\"")));
    assert!(!options.contains(&format!("value=\"{unpriced_id}\"")));

    // Render the page without assignable ticket types
    let event = sample_event(vec![sold_out, inactive, unpriced]);
    let html = sample_page(vec![queued], event, 1).render().unwrap();

    // Check only the placeholder option remains and the empty state is available
    let options = element_html_with(&html, select);
    assert_eq!(options.matches("<option").count(), 1);
    assert!(options.contains("<option value=\"\">Select ticket type</option>"));
    assert!(
        element_text_with(&html, "data-waitlist-invite-ticket-empty")
            .starts_with("No ticket types can be assigned.")
    );
}

#[test]
fn test_list_page_renders_waitlist_range_label() {
    let cases = [
        (1, "1</span> waitlist entry", "</span> waitlist entries"),
        (2, "2</span> waitlist entries", "</span> waitlist entry"),
    ];

    for (count, expected_label, unexpected_label) in cases {
        // Setup the given number of queued entries
        let waitlist = (1..=count)
            .map(|id| entry(Uuid::from_u128(id), None, None))
            .collect::<Vec<_>>();

        // Render the list page
        let event = sample_event_summary(Uuid::from_u128(100));
        let html =
            normalize_whitespace(&sample_page(waitlist, event, count as usize).render().unwrap());

        // Check the range label agrees with the number of visible entries
        assert!(html.contains(expected_label), "{count}");
        assert!(!html.contains(unexpected_label), "{count}");
    }
}

#[test]
fn test_waitlist_row_key_is_stable_for_the_same_user() {
    let user_id = Uuid::max();
    let queued = entry(user_id, None, None);
    let pending_offer = entry(
        user_id,
        Some(Uuid::from_u128(7)),
        Some(EventAdmissionOfferStatus::Pending),
    );
    let expired_offer = entry(
        user_id,
        Some(Uuid::from_u128(8)),
        Some(EventAdmissionOfferStatus::Expired),
    );

    assert_eq!(waitlist_row_key(&queued), format!("waitlist-{user_id}"));
    assert_eq!(waitlist_row_key(&pending_offer), waitlist_row_key(&queued));
    assert_eq!(waitlist_row_key(&expired_offer), waitlist_row_key(&queued));
}

// Helpers.

/// Waitlist entry for the given user and optional admission offer.
fn entry(
    user_id: Uuid,
    admission_offer_id: Option<Uuid>,
    status: Option<EventAdmissionOfferStatus>,
) -> WaitlistEntry {
    WaitlistEntry {
        created_at: Utc::now(),
        event_ticket_type_id: Uuid::nil(),
        ticket_title: "General".to_string(),
        user: User {
            user_id,
            username: "jane".to_string(),
            ..User::default()
        },
        admission_offer_id,
        admission_offer_status: status,
        offer_expires_at: None,
        waitlist_position: None,
    }
}

/// Upcoming event with a waitlist and the given ticket types.
fn sample_event(ticket_types: Vec<EventTicketType>) -> EventSummary {
    EventSummary {
        payment_currency_code: Some("USD".to_string()),
        ticket_types: Some(ticket_types),
        waitlist_enabled: true,
        ..sample_event_summary(Uuid::from_u128(100))
    }
}

/// Waitlist list page for a manager with default filters.
fn sample_page(waitlist: Vec<WaitlistEntry>, event: EventSummary, total: usize) -> ListPage {
    ListPage {
        can_manage_events: true,
        event,
        navigation_links: NavigationLinks::default(),
        refresh_url: "/dashboard/group/events/waitlist".to_string(),
        total,
        waitlist,

        limit: None,
        offset: None,
        sort: None,
        title: None,
        ts_query: None,
    }
}

/// Active, priced, public ticket type with available seats.
fn sample_ticket_type(event_ticket_type_id: Uuid, title: &str) -> EventTicketType {
    EventTicketType {
        active: true,
        availability: EventTicketTypeAvailability::Public,
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
