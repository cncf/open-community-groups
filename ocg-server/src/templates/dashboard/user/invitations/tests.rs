use askama::Template;
use chrono::{TimeZone, Utc};
use chrono_tz::America::Los_Angeles;
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, element_text_with, opening_tag_with},
    types::{
        community::CommunityRole,
        dashboard::user::invitations::{
            CommunityTeamInvitation, EventInvitation, GroupTeamInvitation,
        },
        group::GroupRole,
        payments::ExternalPaymentInfo,
        tests::{
            sample_community_invitation, sample_event_invitation, sample_group_invitation,
            sample_survey_question,
        },
    },
};

use super::ListPage;

/// Offer expiration as the template renders it in the offer timezone.
const EXPIRES_AT_LABEL: &str = "Mar 5, 2030 at 6:00 PM PST";

/// Price confirmation warning shown in ticket offer claim dialogs.
const PRICE_WARNING: &str = "Your price is confirmed when you first claim the offer.";

#[test]
fn test_list_page_names_invitation_in_card_confirmations() {
    // Render one invitation of each kind
    let community_invitation = sample_community_invitation(Uuid::from_u128(3));
    let event_invitation = sample_offer();
    let group_invitation = sample_group_invitation(Uuid::from_u128(4));
    let page = ListPage {
        community_invitations: vec![community_invitation.clone()],
        event_invitations: vec![event_invitation.clone()],
        group_invitations: vec![group_invitation.clone()],
    };
    let html = page.render().unwrap();

    // Check the event offer card decline names the event
    let decline_offer = opening_tag_with(
        &html,
        &format!(
            r#"id="decline-event-offer-card-{}""#,
            event_invitation.admission_offer_id
        ),
    );
    assert!(decline_offer.contains(&format!(
        r#"data-confirm-message="Decline your invitation to {}? Your spot will be released.""#,
        event_invitation.event_name
    )));

    // Check the group card reject names the group
    let reject_group = opening_tag_with(
        &html,
        &format!(r#"id="reject-group-card-{}""#, group_invitation.group_id),
    );
    assert!(reject_group.contains(&format!(
        r#"data-confirm-message="Decline your invitation to join {}?""#,
        group_invitation.group_name
    )));

    // Check the community card reject names the community
    let reject_community = opening_tag_with(
        &html,
        &format!(
            r#"id="reject-community-card-{}""#,
            community_invitation.community_id
        ),
    );
    assert!(reject_community.contains(&format!(
        r#"data-confirm-message="Decline your invitation to join {}?""#,
        community_invitation.community_display_name
    )));
}

#[test]
fn test_list_page_renders_claim_dialog_by_offer_kind() {
    // Setup the cases: (case, simple rsvp, amount, currency, deadline lead, offer label)
    let cases = [
        (
            "paid ticket",
            false,
            Some(2_500),
            Some("USD"),
            "Claim by",
            "USD 25.00",
        ),
        ("simple rsvp", true, None, None, "Confirm by", "RSVP"),
    ];

    for (case, is_simple_rsvp, amount_minor, currency_code, deadline_lead, offer_label) in cases {
        // Render the offer kind
        let mut invitation = sample_offer();
        invitation.amount_minor = amount_minor;
        invitation.currency_code = currency_code.map(ToString::to_string);
        invitation.is_simple_rsvp = is_simple_rsvp;
        let offer_id = invitation.admission_offer_id;
        let html = sample_list_page(invitation).render().unwrap();

        // Check the dialog starts hidden and names itself by its title
        let modal_needle = format!(r#"id="event-offer-modal-{offer_id}""#);
        let modal_tag = opening_tag_with(&html, &modal_needle);
        assert!(modal_tag.contains(r#"aria-hidden="true""#), "{case}");
        assert!(
            modal_tag.contains(&format!(
                r#"aria-labelledby="event-offer-title-{offer_id}""#
            )),
            "{case}"
        );

        // Check the dialog copy for the offer kind
        let modal_text = element_text_with(&html, &modal_needle);
        assert!(
            modal_text.contains(&format!("{deadline_lead} {EXPIRES_AT_LABEL}.")),
            "{case}: {modal_text}"
        );
        assert!(modal_text.contains(offer_label), "{case}: {modal_text}");
        assert_eq!(
            modal_text.contains(PRICE_WARNING),
            !is_simple_rsvp,
            "{case}: {modal_text}"
        );
    }
}

#[test]
fn test_list_page_renders_external_payment_details() {
    // Render an offer with an unpaid external purchase
    let mut invitation = sample_offer();
    invitation.external_payment = Some(ExternalPaymentInfo {
        amount_minor: 2_500,
        currency_code: "USD".to_string(),
        deadline: Utc.with_ymd_and_hms(2030, 3, 7, 20, 0, 0).unwrap(),
        reference: Uuid::from_u128(7),
        url: "https://pay.example.test".to_string(),
        instructions: Some("Pay to <IBAN>".to_string()),
    });
    let offer_id = invitation.admission_offer_id;
    let html = sample_list_page(invitation).render().unwrap();

    // Check the row and card show the reference, deadline and escaped instructions
    for needle in [
        format!(r#"id="event-offer-{offer_id}""#),
        format!(r#"id="event-offer-card-{offer_id}""#),
    ] {
        let text = element_text_with(&html, &needle);
        assert!(
            text.contains("Confirm by Mar 7, 2030 at 12:00 PM PST"),
            "{needle}: {text}"
        );
        assert!(
            text.contains("Reference: 00000000-0000-0000-0000-000000000007"),
            "{needle}: {text}"
        );
        assert!(text.contains("Pay to &#60;IBAN&#62;"), "{needle}: {text}");
    }
    assert!(!html.contains("<IBAN>"));

    // Check the payment page opens in a new tab without an opener
    let payment_link = opening_tag_with(&html, r#"href="https://pay.example.test""#);
    assert!(payment_link.contains(r#"target="_blank""#));
    assert!(payment_link.contains(r#"rel="noopener noreferrer""#));
    assert!(html.contains("Open payment page"));
}

#[test]
fn test_list_page_renders_layout_refresher() {
    // Render the list page
    let html = sample_list_page(sample_offer()).render().unwrap();

    // Check the refresher reloads the whole dashboard layout on the claim event
    // and keeps the claim alert open
    let refresher = opening_tag_with(&html, "data-user-invitations-refresh");
    assert!(refresher.contains(r#"hx-get="/dashboard/user?tab=invitations""#));
    assert!(refresher.contains(r#"hx-trigger="refresh-user-invitations from:body""#));
    assert!(refresher.contains(r##"hx-target="#dashboard-layout""##));
    assert!(refresher.contains(r##"hx-select="#dashboard-layout""##));
    assert!(refresher.contains("data-keeps-alerts"));
}

#[test]
fn test_list_page_shows_team_invitation_display_names() {
    // Render team invitations with multi-word roles
    let community_invitation = CommunityTeamInvitation {
        role: CommunityRole::GroupsManager,
        role_display_name: "Groups Manager".to_string(),
        ..sample_community_invitation(Uuid::from_u128(3))
    };
    let group_invitation = GroupTeamInvitation {
        role: GroupRole::EventsManager,
        role_display_name: "Events Manager".to_string(),
        ..sample_group_invitation(Uuid::from_u128(4))
    };
    let page = ListPage {
        community_invitations: vec![community_invitation],
        event_invitations: vec![],
        group_invitations: vec![group_invitation],
    };
    let html = page.render().unwrap();

    // Check the community and role display names render
    assert!(html.contains("Groups Manager"));
    assert!(html.contains("Events Manager"));
    assert!(html.contains("Test Community"));
    assert!(html.contains("Decline your invitation to join Test Community?"));

    // Check the community slug and role identifiers are not shown
    assert!(!html.contains("groups-manager<"));
    assert!(!html.contains("events-manager<"));
    assert!(!html.contains(">test-community"));
}

#[test]
fn test_list_page_skips_claim_dialog_once_checkout_started() {
    // Render an offer whose checkout can be resumed
    let resume_checkout_url = "https://checkout.example.test/session";
    let mut invitation = sample_offer();
    invitation.resume_checkout_url = Some(resume_checkout_url.to_string());
    let offer_id = invitation.admission_offer_id;
    let html = sample_list_page(invitation).render().unwrap();

    // Check the offer links to checkout instead of opening a claim dialog
    assert!(!html.contains(&format!(r#"id="event-offer-modal-{offer_id}""#)));
    assert!(html.contains(&format!(r#"href="{resume_checkout_url}""#)));
    assert!(html.contains("Continue to checkout"));
}

#[test]
fn test_list_page_summarizes_offer_card_chips() {
    // Setup the cases: (case, simple rsvp, questions count, expected chip)
    let cases = [
        ("simple rsvp", true, 0, "Free RSVP"),
        ("one question", false, 1, "1 question</span>"),
        ("two questions", false, 2, "2 questions"),
    ];

    for (case, is_simple_rsvp, questions_count, expected_chip) in cases {
        // Render the offer card for the case
        let mut invitation = sample_offer();
        invitation.is_simple_rsvp = is_simple_rsvp;
        invitation.registration_questions = (1..=questions_count)
            .map(|n| sample_survey_question(Uuid::from_u128(n)))
            .collect();
        let offer_id = invitation.admission_offer_id;
        let html = sample_list_page(invitation).render().unwrap();

        // Check the card chips
        let card = element_html_with(&html, &format!(r#"id="event-offer-card-{offer_id}""#));
        assert!(
            card.contains(expected_chip),
            "{case}: expected {expected_chip} in {card}"
        );
    }
}

// Helpers.

/// Builds a list page holding only the given event invitation.
fn sample_list_page(event_invitation: EventInvitation) -> ListPage {
    ListPage {
        community_invitations: vec![],
        event_invitations: vec![event_invitation],
        group_invitations: vec![],
    }
}

/// Builds a pending event offer with fixed identifiers and 2030 dates shown in
/// Los Angeles time.
fn sample_offer() -> EventInvitation {
    let mut invitation = sample_event_invitation(Uuid::from_u128(2));
    invitation.admission_offer_id = Uuid::from_u128(1);
    invitation.expires_at = Utc.with_ymd_and_hms(2030, 3, 6, 2, 0, 0).unwrap();
    invitation.starts_at = Some(Utc.with_ymd_and_hms(2030, 3, 10, 18, 0, 0).unwrap());
    invitation.timezone = Los_Angeles;
    invitation
}
