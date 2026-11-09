use std::collections::HashMap;

use askama::Template;
use chrono::{Duration, Utc};
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, element_text_with, normalize_whitespace, opening_tag_with},
    types::{
        dashboard::group::events::{EventCohostsEditor, EventsTab, GroupEvents, PaginatedEvents},
        event::EventSummary,
        pagination::NavigationLinks,
        payments::{EventTicketPriceWindow, EventTicketType, GroupExternalPaymentsContext},
        tests::{sample_event_full, sample_event_summary},
    },
    validation::{MAX_ASSIGNED_EVENT_LABELS, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME},
};

use super::{
    AddPage, EventTicketingMode, ListPage, UpdatePage, event_ticketing_mode,
    is_paid_ticketing_available, requires_external_payments_opt_in,
    requires_external_payments_seller_name,
};

#[test]
fn test_add_page_explains_free_only_ticket_pricing_per_rail() {
    // Setup the pricing hint of each rail
    let stripe_hint = "Set the ticket amount to 0 to make a specific tier free.";
    let opt_in_hint = "until external payments are enabled in group settings";
    let seller_hint = "legal name of the organization collecting external payments is saved";
    let none_hint = "Ticket prices are fixed at 0 until payments are configured.";
    let hints = [stripe_hint, opt_in_hint, seller_hint, none_hint];

    // Setup the rail inputs
    // (case, payments_ready, external payments, expected hint, free only)
    let cases = [
        (
            "stripe ready",
            true,
            GroupExternalPaymentsContext::default(),
            stripe_hint,
            false,
        ),
        (
            "external payments opt-in required",
            false,
            external_payments(true, true, false, None),
            opt_in_hint,
            true,
        ),
        (
            "external payments seller missing",
            false,
            external_payments(true, true, true, None),
            seller_hint,
            true,
        ),
        (
            "no rail configured",
            false,
            GroupExternalPaymentsContext::default(),
            none_hint,
            true,
        ),
    ];

    for (case, payments_ready, external_payments, expected_hint, free_only) in cases {
        // Render the add page for the rail
        let html = sample_add_page(external_payments, payments_ready).render().unwrap();
        let text = normalize_whitespace(&html);

        // Check only the rail's pricing hint is shown
        for hint in hints {
            assert_eq!(text.contains(hint), hint == expected_hint, "{case}: {hint}");
        }

        // Check the ticket types editor is free-only when paid tickets are unavailable
        assert_eq!(
            opening_tag_with(&html, r#"id="ticket-types-ui""#).contains("free-only"),
            free_only,
            "{case}: free-only"
        );
    }
}

#[test]
fn test_add_page_renders_external_payment_fields_for_external_rail() {
    // Render the add page on the external rail
    let html = sample_add_page(
        external_payments(true, true, true, Some("External Payee Co")),
        false,
    )
    .render()
    .unwrap();

    // Check the external payment fields and their limits
    let url_input = opening_tag_with(&html, r#"name="external_payment_url""#);
    assert!(url_input.contains(r#"data-external-ticketing-enabled="true""#));
    assert!(html.contains(r#"name="external_payment_instructions""#));
    let window_input = opening_tag_with(&html, r#"name="external_payment_window_hours""#);
    assert!(window_input.contains(r#"min="1""#));
    assert!(window_input.contains(r#"max="336""#));
    assert!(window_input.contains(r#"placeholder="72""#));

    // Check organizers are told they own tax and receipts
    assert!(
        normalize_whitespace(&html).contains("Organizers are responsible for tax and receipts")
    );

    // Check the Stripe rail renders no external payment fields
    let html = sample_add_page(GroupExternalPaymentsContext::default(), true)
        .render()
        .unwrap();
    assert!(!html.contains(r#"name="external_payment_url""#));
}

#[test]
fn test_add_page_renders_tax_controls_only_for_paid_ticketing() {
    // Setup the rail inputs
    // (case, payments_ready, external payments, tax controls)
    let cases = [
        (
            "stripe ready",
            true,
            GroupExternalPaymentsContext::default(),
            true,
        ),
        (
            "free only",
            false,
            GroupExternalPaymentsContext::default(),
            false,
        ),
    ];

    for (case, payments_ready, external_payments, tax_controls) in cases {
        // Render the add page for the rail
        let html = sample_add_page(external_payments, payments_ready).render().unwrap();

        // Check free-only ticketing renders no tax or discount controls
        if !tax_controls {
            assert!(
                !html.contains(r#"id="manual-tax-rates-fieldset""#),
                "{case}"
            );
            assert!(!html.contains(r#"id="tax_calculation_mode""#), "{case}");
            assert!(!html.contains(r#"id="discount-codes-ui""#), "{case}");
            continue;
        }

        // Check the tax calculation options default to automatic
        let tax_mode = element_html_with(&html, r#"id="tax_calculation_mode""#);
        assert!(
            tax_mode.contains(r#"<option value="automatic" selected>"#),
            "{case}"
        );
        assert!(tax_mode.contains(r#"value="manual""#), "{case}");
        assert!(tax_mode.contains(r#"value="none""#), "{case}");

        // Check the manual tax rates fieldset loads rates and describes its select
        let fieldset = opening_tag_with(&html, r#"id="manual-tax-rates-fieldset""#);
        assert!(
            fieldset.contains(r#"data-tax-rates-url="/dashboard/group/events/tax-rates""#),
            "{case}"
        );
        let rates_select = opening_tag_with(&html, r#"id="manual-tax-rates""#);
        assert!(
            rates_select
                .contains(r#"aria-describedby="manual-tax-rates-help manual-tax-rates-state""#),
            "{case}"
        );

        // Check readiness stays disabled with its reason until the event is saved
        let readiness = r#"data-automatic-tax-readiness-action="check""#;
        let readiness_button = opening_tag_with(&html, readiness);
        assert!(readiness_button.contains("disabled"), "{case}");
        assert!(
            readiness_button.contains(
                r#"aria-label="Save the event before checking whether its venue is ready for automatic tax.""#
            ),
            "{case}"
        );
        assert_eq!(
            element_text_with(&html, readiness),
            "Check readiness",
            "{case}"
        );

        // Check discount codes are offered with paid ticketing
        assert!(html.contains(r#"id="discount-codes-ui""#), "{case}");
    }
}

#[test]
fn test_add_page_seeds_editors_with_defaults_and_limits() {
    // Render the add page
    let html = sample_add_page(GroupExternalPaymentsContext::default(), true)
        .render()
        .unwrap();

    // Check the ticket types editor starts with a General Admission tier
    let ticket_types = opening_tag_with(&html, r#"id="ticket-types-ui""#);
    assert!(ticket_types.contains(r#""seats_total":500,"title":"General Admission""#));

    // Check the questions editor uses the validation limits
    let questions = opening_tag_with(&html, "<questions-editor");
    assert!(questions.contains(&format!(
        r#"prompt-max-length="{MAX_LEN_DESCRIPTION_SHORT}""#
    )));
    assert!(questions.contains(&format!(r#"option-max-length="{MAX_LEN_ENTITY_NAME}""#)));

    // Check the sessions section uses the label selection limit
    let sessions = opening_tag_with(&html, "<sessions-section");
    assert!(sessions.contains(&format!(
        r#"label-max-selected="{MAX_ASSIGNED_EVENT_LABELS}""#
    )));
}

#[test]
fn test_add_page_wires_editor_forms_to_the_save_action() {
    // Render the add page
    let page = sample_add_page(GroupExternalPaymentsContext::default(), true);
    let group_id = page.group_id;
    let html = page.render().unwrap();

    // Check the page root and the save button submit every editor form
    assert!(html.contains(r#"data-event-page="add""#));
    let save_button = opening_tag_with(&html, r#"id="add-event-button""#);
    assert!(save_button.contains(r#"hx-post="/dashboard/group/events/add""#));
    assert!(save_button.contains(r#"hx-include="form[data-event-form]""#));
    assert!(save_button.contains(r#"hx-swap="none""#));

    // Check the back link and the draft header fallbacks
    let back_link = opening_tag_with(&html, r#"id="event-back-link""#);
    assert!(back_link.contains(r#"href="/dashboard/group?tab=events""#));
    assert_eq!(
        element_text_with(&html, r#"id="draft-event-title""#),
        "Untitled event"
    );
    assert_eq!(
        element_text_with(&html, r#"id="draft-event-date""#),
        "Date not set yet"
    );

    // Check the co-hosts selector starts empty for the current group
    let cohosts = opening_tag_with(&html, "<cohosts-selector");
    assert!(cohosts.contains(r#"selected-cohosts="[]""#));
    assert!(cohosts.contains(r#"revision="0""#));
    assert!(cohosts.contains(&format!(r#"current-group-id="{group_id}""#)));

    // Check every editor form is included in the save request
    for id in [
        "details-form",
        "date-venue-form",
        "cohosts-form",
        "contributors-form",
        "payments-form",
        "questions-form",
        "labels-form",
        "cfs-form",
        "sessions-form",
    ] {
        let form = opening_tag_with(&html, &format!(r#"id="{id}""#));
        assert!(form.contains("data-event-form"), "{id}");
    }

    // Check the labels editor lives in the labels form only
    assert!(element_html_with(&html, r#"id="labels-form""#).contains(r#"id="labels-editor""#));
    assert!(!element_html_with(&html, r#"id="cfs-form""#).contains(r#"id="labels-editor""#));
}

#[test]
fn test_list_page_confirm_copy_follows_payment_rail() {
    // Setup the single-event confirm copy of each rail
    let cancel_intro = "Cancel this event? This cannot be undone. \
        All attendee registrations will be canceled immediately.";
    let stripe_cancel = format!(
        "{cancel_intro} Full refunds for eligible paid purchases will be queued \
        and may take time to process."
    );
    let stripe_unpublish =
        "Unpublish this event? Existing attendees and ticket purchases will be retained.";
    let external_cancel = format!(
        "{cancel_intro} Any external payments already received must be returned \
        by an organizer outside OCG."
    );
    let external_unpublish = "Unpublish this event? Pending reservations awaiting external \
        payment will expire and those attendees will be told not to pay. \
        Confirmed attendees will remain registered.";

    // Setup the rail inputs
    // (case, has external payment, expected cancel copy, expected unpublish copy)
    let cases = [
        ("stripe", false, stripe_cancel, stripe_unpublish),
        ("external", true, external_cancel, external_unpublish),
    ];

    for (case, has_external_payment, cancel_copy, unpublish_copy) in cases {
        // Render the list page with one published upcoming event
        let event_id = Uuid::from_u128(1);
        let html = sample_list_page(EventSummary {
            has_external_payment,
            published: true,
            ..sample_event_summary(event_id)
        })
        .render()
        .unwrap();
        let cancel = opening_tag_with(&html, &format!(r#"id="cancel-event-{event_id}""#));
        let unpublish = opening_tag_with(&html, &format!(r#"id="unpublish-event-{event_id}""#));

        // Check each action asks with its rail's copy
        assert!(
            cancel.contains(&format!(r#"data-single-message="{cancel_copy}""#)),
            "{case}: cancel"
        );
        assert!(
            unpublish.contains(&format!(r#"data-single-message="{unpublish_copy}""#)),
            "{case}: unpublish"
        );

        // Check the cancel confirmation labels its choices
        assert!(
            cancel.contains(r#"data-confirm-text="Cancel event""#),
            "{case}"
        );
        assert!(
            cancel.contains(r#"data-cancel-text="Keep event""#),
            "{case}"
        );
        assert!(
            cancel.contains(r#"data-series-scope-text="Non-completed events in series""#),
            "{case}"
        );
    }
}

#[test]
#[allow(clippy::too_many_lines)]
fn test_ticketing_rail_helpers_follow_rail_selection() {
    use EventTicketingMode::{External, Stripe, Unavailable};

    let named = Some("External Payee Co");
    // (case, payments_ready, external payments, mode, available, opt_in, seller_name)
    let cases = [
        (
            "no rail configured",
            false,
            GroupExternalPaymentsContext::default(),
            Unavailable,
            false,
            false,
            false,
        ),
        (
            "stripe ready, country not allowlisted",
            true,
            external_payments(true, false, false, named),
            Stripe,
            true,
            false,
            false,
        ),
        (
            "stripe ready, country not allowlisted, nameless",
            true,
            external_payments(true, false, false, None),
            Stripe,
            true,
            false,
            false,
        ),
        (
            "stripe not ready, country not allowlisted",
            false,
            external_payments(true, false, false, None),
            Unavailable,
            false,
            false,
            false,
        ),
        (
            "allowlisted but external payments not configured",
            false,
            external_payments(false, true, false, None),
            Unavailable,
            false,
            false,
            false,
        ),
        (
            "allowlisted and opted out, stripe ready",
            true,
            external_payments(true, true, false, named),
            Stripe,
            true,
            false,
            false,
        ),
        (
            "allowlisted and opted out, stripe not ready",
            false,
            external_payments(true, true, false, None),
            Unavailable,
            false,
            true,
            false,
        ),
        (
            "opted in and named, stripe ready",
            true,
            external_payments(true, true, true, named),
            External,
            true,
            false,
            false,
        ),
        (
            "opted in and named, stripe not ready",
            false,
            external_payments(true, true, true, named),
            External,
            true,
            false,
            false,
        ),
        // An opted-in group stays on the external rail even when Stripe is
        // ready, so paid tickets wait on the seller name
        (
            "opted in and nameless, stripe ready",
            true,
            external_payments(true, true, true, None),
            External,
            false,
            false,
            true,
        ),
        (
            "opted in and nameless, stripe not ready",
            false,
            external_payments(true, true, true, None),
            External,
            false,
            false,
            true,
        ),
    ];

    for (case, ready, ctx, mode, available, opt_in, seller_name) in cases {
        assert_eq!(event_ticketing_mode(ready, &ctx), mode, "{case}: mode");
        assert_eq!(
            is_paid_ticketing_available(ready, &ctx),
            available,
            "{case}: available"
        );
        assert_eq!(
            requires_external_payments_opt_in(ready, &ctx),
            opt_in,
            "{case}: opt-in"
        );
        assert_eq!(
            requires_external_payments_seller_name(ready, &ctx),
            seller_name,
            "{case}: seller name"
        );
    }
}

#[test]
fn test_update_page_explains_read_only_paid_ticketing_per_rail() {
    // Setup the read-only message of each rail
    let opt_in_message = "enable external payments in group settings and add a payment URL";
    let seller_message =
        "until the legal name of the organization collecting external payments is saved";
    let none_message = "until server payments and a matching group recipient are configured";
    let messages = [opt_in_message, seller_message, none_message];

    // Setup the rail inputs
    // (case, payments_ready, external payments, expected message)
    let cases = [
        (
            "stripe ready",
            true,
            GroupExternalPaymentsContext::default(),
            None,
        ),
        (
            "external payments opt-in required",
            false,
            external_payments(true, true, false, None),
            Some(opt_in_message),
        ),
        (
            "external payments seller missing",
            false,
            external_payments(true, true, true, None),
            Some(seller_message),
        ),
        (
            "no rail configured",
            false,
            GroupExternalPaymentsContext::default(),
            Some(none_message),
        ),
    ];

    for (case, payments_ready, external_payments, expected_message) in cases {
        // Setup a priced event without an external payment URL
        let mut page = sample_update_page(external_payments, payments_ready);
        page.event.ticket_types = Some(vec![priced_ticket_type()]);

        // Check the inputs match the template's paid_ticketing_read_only flag
        assert!(page.event.is_paid_capable(), "{case}: paid capable");
        assert!(page.event.external_payment_url.is_none(), "{case}: url");
        assert_eq!(
            page.is_paid_ticketing_available(),
            expected_message.is_none(),
            "{case}: available"
        );

        // Render the update page for the rail
        let text = normalize_whitespace(&page.render().unwrap());

        // Check only the rail's read-only message is shown
        for message in messages {
            assert_eq!(
                text.contains(message),
                expected_message == Some(message),
                "{case}: {message}"
            );
        }
    }
}

#[test]
fn test_update_page_marks_past_events_for_meeting_details() {
    // Setup an upcoming and a past event with meetings enabled
    let upcoming = sample_update_page(GroupExternalPaymentsContext::default(), true);
    let mut past = sample_update_page(GroupExternalPaymentsContext::default(), true);
    past.event.starts_at = Some(Utc::now() - Duration::days(1) - Duration::hours(1));
    past.event.ends_at = Some(Utc::now() - Duration::days(1));

    // (case, page, past)
    let cases = [("upcoming", upcoming, false), ("past", past, true)];

    for (case, mut page, is_past) in cases {
        // Render the update page with meetings enabled
        page.meetings_enabled = true;
        let html = page.render().unwrap();

        // Check the meeting and session editors carry the past-event state hook
        for needle in [r#"id="online-event-details""#, "<sessions-section"] {
            let tag = opening_tag_with(&html, needle);
            assert_eq!(
                tag.split_whitespace().any(|token| token == "event-past"),
                is_past,
                "{case}: {needle}"
            );
        }
    }
}

#[test]
fn test_update_page_renders_event_id_in_details() {
    // Render the update page
    let page = sample_update_page(GroupExternalPaymentsContext::default(), true);
    let event_id = page.event.event_id;
    let text = normalize_whitespace(&page.render().unwrap());

    // Check the event details title shows the event id
    assert!(text.contains(&format!(">{event_id}</span>)")));
}

#[test]
#[allow(clippy::too_many_lines)]
fn test_update_page_renders_external_payment_fields_for_its_rail() {
    // Setup the rail notices
    let unavailable_notice = "External payments are no longer available for this group.";
    let seller_notice = "Save the legal name of the organization collecting external payments";
    let notices = [unavailable_notice, seller_notice];
    let named = Some("External Payee Co");
    let stored_url = Some("https://pay.example.test");

    // Setup the rail inputs
    // (case, payments_ready, external payments, stored url, external ticketing enabled, notice)
    let cases = [
        (
            "external rail",
            false,
            external_payments(true, true, true, named),
            None,
            Some("true"),
            None,
        ),
        (
            "stored url on a stripe ready group",
            true,
            GroupExternalPaymentsContext::default(),
            stored_url,
            Some("false"),
            Some(unavailable_notice),
        ),
        (
            "external payments seller missing",
            false,
            external_payments(true, true, true, None),
            None,
            Some("true"),
            Some(seller_notice),
        ),
        (
            "stripe without url",
            true,
            GroupExternalPaymentsContext::default(),
            None,
            None,
            None,
        ),
    ];

    for (case, payments_ready, external_payments, url, ticketing_enabled, notice) in cases {
        // Render the update page for a priced event on the rail, so the
        // tickets form renders even when paid ticketing is unavailable
        let mut page = sample_update_page(external_payments, payments_ready);
        page.event.external_payment_url = url.map(str::to_string);
        page.event.ticket_types = Some(vec![priced_ticket_type()]);
        let html = page.render().unwrap();
        let text = normalize_whitespace(&html);

        // Check only the rail's notice is shown
        for expected in notices {
            assert_eq!(
                text.contains(expected),
                notice == Some(expected),
                "{case}: {expected}"
            );
        }

        // Check the Stripe rail renders no external payment fields
        let Some(ticketing_enabled) = ticketing_enabled else {
            assert!(
                !html.contains(r#"name="external_payment_url_present""#),
                "{case}"
            );
            continue;
        };

        // Check the external payment URL field and its stored value
        assert!(
            html.contains(r#"name="external_payment_url_present""#),
            "{case}"
        );
        let url_input = opening_tag_with(&html, r#"name="external_payment_url""#);
        assert!(
            url_input.contains(&format!(
                r#"data-external-ticketing-enabled="{ticketing_enabled}""#
            )),
            "{case}"
        );
        if let Some(url) = url {
            assert!(url_input.contains(&format!(r#"value="{url}""#)), "{case}");
        }
    }

    // Render the external rail with a restored payment setup
    let mut page = sample_update_page(external_payments(true, true, true, named), false);
    page.event.external_payment_instructions = Some("Pay by bank transfer".to_string());
    page.event.external_payment_window_hours = Some(48);
    let html = page.render().unwrap();

    // Check the restored instructions and payment window
    assert_eq!(
        element_text_with(&html, r#"id="external_payment_instructions""#),
        "Pay by bank transfer"
    );
    let window_input = opening_tag_with(&html, r#"name="external_payment_window_hours""#);
    assert!(window_input.contains(r#"value="48""#));
    assert!(window_input.contains(r#"max="336""#));
}

#[test]
fn test_update_page_wires_editor_forms_and_limits() {
    // Render the update page
    let page = sample_update_page(GroupExternalPaymentsContext::default(), true);
    let event_id = page.event.event_id;
    let html = page.render().unwrap();

    // Check the save button submits every editor form to the event update
    let save_button = opening_tag_with(&html, r#"id="update-event-button""#);
    assert!(save_button.contains(&format!(
        r#"hx-put="/dashboard/group/events/{event_id}/update""#
    )));
    assert!(save_button.contains(r#"hx-include="form[data-event-form]""#));

    // Check every editor form is included in the save request
    for id in [
        "details-form",
        "date-venue-form",
        "cohosts-form",
        "contributors-form",
        "payments-form",
        "questions-form",
        "labels-form",
        "cfs-form",
        "sessions-form",
    ] {
        let form = opening_tag_with(&html, &format!(r#"id="{id}""#));
        assert!(form.contains("data-event-form"), "{id}");
    }

    // Check the questions editor uses the validation limits
    let questions = opening_tag_with(&html, "<questions-editor");
    assert!(questions.contains(&format!(
        r#"prompt-max-length="{MAX_LEN_DESCRIPTION_SHORT}""#
    )));
    assert!(questions.contains(&format!(r#"option-max-length="{MAX_LEN_ENTITY_NAME}""#)));

    // Check the sessions section uses the label selection limit
    let sessions = opening_tag_with(&html, "<sessions-section");
    assert!(sessions.contains(&format!(
        r#"label-max-selected="{MAX_ASSIGNED_EVENT_LABELS}""#
    )));
}

// Helpers.

/// External payments context for the given flags and seller name.
fn external_payments(
    configured: bool,
    eligible: bool,
    enabled: bool,
    seller_display_name: Option<&str>,
) -> GroupExternalPaymentsContext {
    GroupExternalPaymentsContext {
        configured,
        eligible,
        enabled,
        country_code: Some("KR".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: seller_display_name.map(str::to_string),
    }
}

/// Ticket type with one nonzero price window.
fn priced_ticket_type() -> EventTicketType {
    EventTicketType {
        active: true,
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        title: "General Admission".to_string(),

        price_windows: vec![EventTicketPriceWindow {
            amount_minor: 2_500,
            event_ticket_price_window_id: Uuid::new_v4(),
            ..Default::default()
        }],
        ..Default::default()
    }
}

/// Add page for the given payment rail inputs, with empty option lists.
fn sample_add_page(
    external_payments: GroupExternalPaymentsContext,
    payments_ready: bool,
) -> AddPage {
    AddPage {
        can_manage_events: true,
        categories: vec![],
        communities: vec![],
        event_kinds: vec![],
        external_payments,
        group_id: Uuid::new_v4(),
        meetings_enabled: false,
        meetings_max_participants: HashMap::new(),
        payment_currency_codes: vec![],
        payments_ready,
        session_kinds: vec![],
        sponsors: vec![],
        team_members: vec![],
        timezones: vec![],
    }
}

/// Upcoming events list page for a manager, listing only the given event.
fn sample_list_page(event: EventSummary) -> ListPage {
    ListPage {
        can_manage_events: true,
        events: GroupEvents {
            past: PaginatedEvents {
                events: vec![],
                total: 0,
            },
            upcoming: PaginatedEvents {
                events: vec![event],
                total: 1,
            },
        },
        events_tab: EventsTab::Upcoming,
        past_navigation_links: NavigationLinks::default(),
        upcoming_navigation_links: NavigationLinks::default(),

        past_offset: None,
        upcoming_offset: None,
    }
}

/// Update page for an upcoming event on the given payment rail inputs, with
/// empty option lists.
fn sample_update_page(
    external_payments: GroupExternalPaymentsContext,
    payments_ready: bool,
) -> UpdatePage {
    UpdatePage {
        approved_submissions: vec![],
        can_manage_events: true,
        categories: vec![],
        cfs_submission_statuses: vec![],
        cohosts: EventCohostsEditor::default(),
        communities: vec![],
        current_user_id: Uuid::new_v4(),
        event: sample_event_full(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()),
        event_kinds: vec![],
        external_payments,
        meetings_enabled: false,
        meetings_max_participants: HashMap::new(),
        payment_currency_codes: vec![],
        payments_ready,
        session_kinds: vec![],
        show_invitation_requests_tab: false,
        show_waitlist_tab: false,
        sponsors: vec![],
        team_members: vec![],
        timezones: vec![],
    }
}
