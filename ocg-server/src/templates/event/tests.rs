use std::collections::BTreeMap;

use chrono::{DateTime, TimeZone, Utc};
use chrono_tz::{America::Los_Angeles, Europe::Madrid, Tz};
use serde_json::to_value;
use uuid::Uuid;

use crate::{
    test_util::{element_html_with, element_text_with, opening_tag_with},
    types::{
        community::CommunitySummary,
        event::{LegacyUser, Session, Speaker},
        group::GroupSummary,
        inbox::InboxContactViewer,
        payments::{
            EventTicketCurrentPrice, EventTicketPriceWindow, EventTicketType,
            EventTicketTypeAvailability, TicketTaxBehavior, TicketTaxCalculationMode,
        },
        questionnaire::{QuestionnaireQuestion, QuestionnaireQuestionKind},
        tests::{sample_event_summary, sample_template_user_with_id},
        user::User,
    },
    validation::MAX_LEN_INBOX_MESSAGE,
};

use super::*;

#[test]
fn test_cfs_modal_renders_profile_link_only_for_incomplete_profiles() {
    // (case, profile complete, expected profile links)
    let cases = [
        ("incomplete profile", false, 1),
        ("complete profile", true, 0),
    ];

    for (case, profile_complete, expected_links) in cases {
        // Render the modal notice for a signed-in user
        let template = CfsModal {
            event: sample_event_summary(Uuid::nil()),
            labels: vec![],
            session_proposals: vec![],
            user: UserMenuState {
                logged_in: true,
                profile_complete,
                ..Default::default()
            },
            notice: Some("Proposal submitted.".into()),
        };
        let body = template.render().unwrap();

        // Check the notice and the profile link count
        assert!(body.contains("Proposal submitted."), "{case}");
        assert_eq!(
            body.matches(r#"href="/dashboard/user?tab=account""#).count(),
            expected_links,
            "{case}"
        );
    }
}

#[test]
fn test_contact_modal_renders_form_with_server_message_limit() {
    // Render the form for a signed-in viewer allowed to start a conversation
    let template = ContactModal {
        user: UserMenuState {
            logged_in: true,
            ..Default::default()
        },
        context: Some(sample_contact_context()),
        sent_inbox_conversation_id: None,
    };
    let html = template.render().unwrap();

    // Check the labelled message field states the server character limit
    assert!(html.contains(r#"<label for="contact-body""#));
    assert!(
        element_text_with(&html, r#"id="contact-body-help""#)
            .contains(&format!("up to {MAX_LEN_INBOX_MESSAGE} characters"))
    );

    // Check the cancel control closes the modal
    let cancel_button = opening_tag_with(&html, r#"id="cancel-contact-modal""#);
    assert!(cancel_button.contains(r#"data-modal-toggle="contact-modal""#));
}

#[test]
fn test_event_person_marks_only_legacy_bio_as_html() {
    let legacy_user = sample_legacy_user(Some("Legacy Speaker"));
    let user = sample_named_user(1, "platform-speaker", Some("Platform Speaker"));

    assert!(EventPerson::Legacy(&legacy_user).bio_is_html());
    assert!(!EventPerson::User(&user).bio_is_html());
}

#[test]
fn test_event_person_serializes_like_source_payload() {
    // Setup a legacy person and a platform user with a bio
    let legacy_user = sample_legacy_user(Some("Legacy Speaker"));
    let user = User {
        bio: Some("Platform bio".to_string()),
        ..sample_named_user(1, "platform-speaker", Some("Platform Speaker"))
    };

    // Check each variant serializes exactly like the value it wraps
    assert_eq!(
        to_value(EventPerson::Legacy(&legacy_user)).unwrap(),
        to_value(&legacy_user).unwrap()
    );
    assert_eq!(
        to_value(EventPerson::User(&user)).unwrap(),
        to_value(&user).unwrap()
    );
}

#[test]
fn test_preview_title_uses_event_date_in_event_timezone() {
    let page = sample_page(
        Some(Utc.with_ymd_and_hms(2030, 3, 6, 7, 30, 0).unwrap()),
        Los_Angeles,
    );

    assert_eq!(page.preview_title(), "Test Event - March 5");
}

#[test]
fn test_preview_title_without_start_date_uses_event_name() {
    let page = sample_page(None, chrono_tz::UTC);

    assert_eq!(page.preview_title(), "Test Event");
}

#[test]
fn test_preview_description_uses_group_and_community_names() {
    let page = sample_page(None, chrono_tz::UTC);

    assert_eq!(
        page.preview_description(),
        "Test Group in Test Community community. Open Community Groups, where Open Source communities thrive."
    );
}

#[test]
fn test_open_graph_image_url_prefers_group_image_over_community_image() {
    // (case, group image, community image, expected)
    let cases = [
        (
            "group image",
            Some("/images/group.png"),
            Some("/images/community.png"),
            Some("https://example.test/images/og/group.png"),
        ),
        (
            "community image fallback",
            None,
            Some("/images/community.png"),
            Some("https://example.test/images/og/community.png"),
        ),
        ("no image", None, None, None),
    ];

    for (case, group_image, community_image, expected) in cases {
        let mut page = sample_page(None, chrono_tz::UTC);
        page.event.group.og_image_url = group_image.map(str::to_string);
        page.event.community.og_image_url = community_image.map(str::to_string);

        assert_eq!(page.open_graph_image_url().as_deref(), expected, "{case}");
    }
}

#[test]
fn test_public_featured_speakers_and_organizers_skip_blank_names() {
    // Setup featured speakers and organizers with present, missing and blank names
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.speakers = vec![
        sample_speaker(
            true,
            sample_named_user(1, "featured-speaker", Some("Featured")),
        ),
        sample_speaker(true, sample_named_user(2, "nameless-featured", None)),
        sample_speaker(true, sample_named_user(3, "blank-featured", Some("  "))),
        sample_speaker(
            false,
            sample_named_user(4, "regular-speaker", Some("Regular")),
        ),
    ];
    page.event.organizers = vec![
        sample_named_user(5, "nameless-organizer", None),
        sample_named_user(6, "organizer", Some("Organizer")),
        sample_named_user(7, "blank-organizer", Some("\t")),
    ];

    // Check only named featured speakers and organizers are listed
    let featured_speakers: Vec<&str> = page
        .public_featured_speakers()
        .into_iter()
        .map(|user| user.username.as_str())
        .collect();
    assert_eq!(featured_speakers, ["featured-speaker"]);
    let organizers: Vec<&str> = page
        .public_organizers()
        .into_iter()
        .map(|user| user.username.as_str())
        .collect();
    assert_eq!(organizers, ["organizer"]);
}

#[test]
fn test_public_hosts_lists_legacy_then_named_hosts() {
    // Setup legacy and platform hosts with present, missing and blank names
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.hosts = vec![
        sample_named_user(1, "platform-host", Some("Platform Host")),
        sample_named_user(2, "nameless-host", None),
        sample_named_user(3, "blank-host", Some(" ")),
    ];
    page.event.legacy_hosts = Some(vec![
        sample_legacy_user(Some("Legacy Host")),
        sample_legacy_user(None),
        sample_legacy_user(Some("  ")),
    ]);

    // Check named legacy hosts come first, marked as HTML bios
    let hosts: Vec<_> = page.public_hosts().iter().map(person_summary).collect();
    assert_eq!(
        hosts,
        [(true, Some("Legacy Host")), (false, Some("Platform Host"))]
    );
}

#[test]
fn test_public_regular_speakers_lists_legacy_then_non_featured_named() {
    // Setup legacy, featured and regular speakers with present, missing and blank names
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.legacy_speakers = Some(vec![
        sample_legacy_user(Some("Legacy Speaker")),
        sample_legacy_user(None),
        sample_legacy_user(Some(" ")),
    ]);
    page.event.speakers = vec![
        sample_speaker(
            true,
            sample_named_user(1, "featured-speaker", Some("Featured")),
        ),
        sample_speaker(
            false,
            sample_named_user(2, "regular-speaker", Some("Regular")),
        ),
        sample_speaker(false, sample_named_user(3, "nameless-speaker", None)),
        sample_speaker(false, sample_named_user(4, "blank-speaker", Some("\n "))),
    ];

    // Check named legacy speakers come first, followed by named regular speakers
    let speakers: Vec<_> = page.public_regular_speakers().iter().map(person_summary).collect();
    assert_eq!(
        speakers,
        [(true, Some("Legacy Speaker")), (false, Some("Regular"))]
    );
}

#[test]
fn test_page_breadcrumb_pairs_banners_with_the_chosen_level_dark_variant() {
    // Setup cases: (label, event desktop pair, event mobile pair, group desktop pair,
    // group mobile pair, expected desktop, expected mobile), where the community
    // pairs are always (c, c-dark) and (cm, cm-dark)
    let cases = [
        (
            "event pairs",
            (Some("e"), Some("e-dark")),
            (Some("em"), Some("em-dark")),
            (Some("g"), Some("g-dark")),
            (Some("gm"), Some("gm-dark")),
            ("e", Some("e-dark")),
            ("em", Some("em-dark")),
        ),
        (
            "event light without dark while the group has a dark",
            (Some("e"), None),
            (Some("em"), None),
            (Some("g"), Some("g-dark")),
            (Some("gm"), Some("gm-dark")),
            ("e", None),
            ("em", None),
        ),
        (
            "group light without dark while the community has a dark",
            (None, None),
            (None, None),
            (Some("g"), None),
            (Some("gm"), None),
            ("g", None),
            ("gm", None),
        ),
        (
            "orphan darks fall through to the community pairs",
            (None, Some("e-dark")),
            (None, Some("em-dark")),
            (None, Some("g-dark")),
            (None, Some("gm-dark")),
            ("c", Some("c-dark")),
            ("cm", Some("cm-dark")),
        ),
        (
            "desktop and mobile resolve independently",
            (Some("e"), Some("e-dark")),
            (None, None),
            (None, None),
            (Some("gm"), None),
            ("e", Some("e-dark")),
            ("gm", None),
        ),
    ];

    for (label, event_desktop, event_mobile, group_desktop, group_mobile, desktop, mobile) in cases
    {
        // Setup the case banners on every level
        let url = |token: &str| format!("https://example.test/{token}.png");
        let mut page = sample_page(None, chrono_tz::UTC);
        page.event.banner_dark_url = event_desktop.1.map(url);
        page.event.banner_mobile_dark_url = event_mobile.1.map(url);
        page.event.banner_mobile_url = event_mobile.0.map(url);
        page.event.banner_url = event_desktop.0.map(url);
        page.event.group.banner_dark_url = group_desktop.1.map(url);
        page.event.group.banner_mobile_dark_url = group_mobile.1.map(url);
        page.event.group.banner_mobile_url = group_mobile.0.map(url);
        page.event.group.banner_url = group_desktop.0.map(url);
        page.event.community.banner_dark_url = Some(url("c-dark"));
        page.event.community.banner_mobile_dark_url = Some(url("cm-dark"));
        page.event.community.banner_mobile_url = url("cm");
        page.event.community.banner_url = url("c");

        // Render the event page and keep its breadcrumb
        let body = page.render().unwrap();
        let breadcrumb = opening_tag_with(&body, "<breadcrumb-nav");

        // Check each banner carries only the dark variant of its own level
        assert_eq!(
            attribute_value(breadcrumb, "banner-url"),
            Some(url(desktop.0).as_str()),
            "{label}"
        );
        assert_eq!(
            attribute_value(breadcrumb, "banner-dark-url"),
            desktop.1.map(url).as_deref(),
            "{label}"
        );
        assert_eq!(
            attribute_value(breadcrumb, "banner-mobile-url"),
            Some(url(mobile.0).as_str()),
            "{label}"
        );
        assert_eq!(
            attribute_value(breadcrumb, "banner-mobile-dark-url"),
            mobile.1.map(url).as_deref(),
            "{label}"
        );
    }
}

#[test]
fn test_page_breadcrumb_strips_emoji_from_group_name() {
    // Render an event whose group name contains an emoji
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.group.name = "Rust Group 🦀".to_string();
    let body = page.render().unwrap();

    // Check the group crumb keeps the name without the emoji
    let breadcrumb = opening_tag_with(&body, "<breadcrumb-nav");
    assert!(breadcrumb.contains("Rust Group"));
    assert!(!breadcrumb.contains('🦀'));
}

#[test]
fn test_page_logo_renders_dark_variant_only_with_dark_logo() {
    // Setup logo URLs
    let logo_url = "https://example.test/event-logo.png";
    let logo_dark_url = "https://example.test/event-logo-dark.png";

    // Render the event page without a dark logo
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.logo_url = logo_url.to_string();
    let body = page.render().unwrap();

    // Check the plated logo renders alone and unmarked
    assert!(opening_tag_with(&body, &format!(r#"src="{logo_url}""#)).starts_with("<img"));
    assert!(!body.contains("data-theme-image"));

    // Render the event page with a dark logo
    page.event.logo_dark_url = Some(logo_dark_url.to_string());
    let body = page.render().unwrap();

    // Check the marked plated logo precedes the unplated lazy dark logo
    let light = element_html_with(&body, r#"data-theme-image="light""#);
    assert!(opening_tag_with(light, "data-theme-image").contains("plate"));
    assert!(opening_tag_with(light, &format!(r#"src="{logo_url}""#)).starts_with("<img"));
    let dark = element_html_with(&body, r#"data-theme-image="dark""#);
    assert!(!opening_tag_with(dark, "data-theme-image").contains("plate"));
    let dark_image = opening_tag_with(dark, &format!(r#"src="{logo_dark_url}""#));
    assert!(dark_image.starts_with("<img"));
    assert!(dark_image.contains(r#"loading="lazy""#));
    assert!(body.find(r#"data-theme-image="light""#) < body.find(r#"data-theme-image="dark""#));
    assert_eq!(body.matches("data-theme-image").count(), 2);
}

#[test]
fn test_page_omits_people_sections_without_public_names() {
    // Setup speakers, hosts and organizers with missing or blank names only
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.hosts = vec![sample_named_user(1, "blank-host", Some(" "))];
    page.event.legacy_hosts = Some(vec![sample_legacy_user(None)]);
    page.event.legacy_speakers = Some(vec![sample_legacy_user(Some("\t"))]);
    page.event.organizers = vec![sample_named_user(2, "nameless-organizer", None)];
    page.event.speakers = vec![
        sample_speaker(true, sample_named_user(3, "nameless-featured", None)),
        sample_speaker(false, sample_named_user(4, "blank-speaker", Some("  "))),
    ];

    // Render the event page
    let body = page.render().unwrap();

    // Check no people section or chip is rendered
    assert!(!body.contains("<user-chip"));
    assert!(!body.contains("featured-speakers-section"));
    assert!(!body.contains("regular-speakers-grid"));
    assert!(!body.contains("Hosts"));
    assert!(!body.contains("Organizers"));
}

#[test]
fn test_page_renders_calendar_year_in_iso_week_of_next_year() {
    // December 30, 2030 belongs to the first ISO week of 2031
    let page = sample_page(
        Some(Utc.with_ymd_and_hms(2030, 12, 30, 18, 0, 0).unwrap()),
        chrono_tz::UTC,
    );

    let body = page.render().unwrap();

    assert!(body.contains("30, 2030"));
    assert!(!body.contains("2031"));
}

#[test]
fn test_page_renders_host_for_paid_event_with_seller() {
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.seller_display_name = Some("Example Payee <Ltd>".to_string());
    page.event.ticket_types = Some(vec![sample_ticket_type(1_500)]);

    let body = page.render().unwrap();

    assert!(body.contains("data-event-host"));
    assert!(body.contains("This event is hosted by"));
    assert!(body.contains("Example Payee &#60;Ltd&#62;"));
}

#[test]
fn test_page_hides_host_for_free_event() {
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.seller_display_name = Some("Example Payee".to_string());
    page.event.ticket_types = Some(vec![sample_ticket_type(0)]);

    let body = page.render().unwrap();

    assert!(!body.contains("data-event-host"));
    assert!(!body.contains("Example Payee"));
}

#[test]
fn test_page_hides_host_for_paid_event_without_seller() {
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.ticket_types = Some(vec![sample_ticket_type(1_500)]);

    let body = page.render().unwrap();

    assert!(!body.contains("data-event-host"));
}

#[test]
fn test_page_disables_discount_code_for_approval_events() {
    // (case, attendee approval required, expected disabled)
    let cases = [
        ("approval", true, true),
        ("sellable non-approval", false, false),
    ];

    for (case, attendee_approval_required, expected_disabled) in cases {
        // Render a paid upcoming event with one sellable ticket type
        let mut page = sample_upcoming_page(chrono_tz::UTC);
        page.event.attendee_approval_required = attendee_approval_required;
        page.event.payment_currency_code = Some("USD".to_string());
        page.event.ticket_types = Some(vec![sample_priced_ticket_type(1_500)]);
        let html = page.render().unwrap();

        // Check the cached discount field state
        let discount_input = opening_tag_with(&html, r#"id="discount-code-main""#);
        assert_eq!(
            discount_input.contains("disabled"),
            expected_disabled,
            "{case}"
        );
    }
}

#[test]
fn test_page_discloses_additional_ticket_tax() {
    // (case, tax behavior, tax calculation mode, expected disclosed)
    let cases = [
        (
            "exclusive automatic",
            TicketTaxBehavior::Exclusive,
            TicketTaxCalculationMode::Automatic,
            true,
        ),
        (
            "inclusive",
            TicketTaxBehavior::Inclusive,
            TicketTaxCalculationMode::Automatic,
            false,
        ),
        (
            "no tax calculation",
            TicketTaxBehavior::Exclusive,
            TicketTaxCalculationMode::None,
            false,
        ),
    ];

    for (case, tax_behavior, tax_calculation_mode, expected_disclosed) in cases {
        // Render a paid upcoming event with the case tax settings
        let mut page = sample_upcoming_page(chrono_tz::UTC);
        page.event.payment_currency_code = Some("USD".to_string());
        page.event.tax_behavior = tax_behavior;
        page.event.tax_calculation_mode = tax_calculation_mode;
        page.event.ticket_types = Some(vec![sample_priced_ticket_type(1_500)]);
        let html = page.render().unwrap();

        // Check the ticket dialog note and the phone bar price suffix
        assert_eq!(
            html.contains("Tax is added at checkout."),
            expected_disclosed,
            "{case}"
        );
        assert_eq!(
            html.contains("</span>&nbsp;+ tax"),
            expected_disclosed,
            "{case}"
        );
    }
}

#[test]
fn test_page_includes_registration_answers_only_with_questions() {
    // (case, registration questions, expected include)
    let cases = [
        ("with questions", vec![sample_registration_question()], true),
        ("no questions", vec![], false),
    ];

    for (case, registration_questions, expected_include) in cases {
        // Render an upcoming event with the case registration questions
        let mut page = sample_upcoming_page(chrono_tz::UTC);
        page.event.registration_questions = registration_questions;
        let html = page.render().unwrap();

        // Check the attend action submits answers only when questions exist
        assert_eq!(
            html.contains(r##"hx-include="#registration-answers-input-main""##),
            expected_include,
            "{case}"
        );
    }
}

#[test]
fn test_page_renders_attendance_check_retry_control() {
    // Render an upcoming event
    let page = sample_upcoming_page(chrono_tz::UTC);
    let html = page.render().unwrap();

    // Check Retry starts hidden and is described by its popover; `hidden` is the state
    // contract the attendance script toggles
    let retry_button = opening_tag_with(&html, r#"data-attendance-role="retry-btn""#);
    assert!(retry_button.contains(r#"class="hidden "#));
    assert!(retry_button.contains(r#"aria-describedby="attendance-check-details-main""#));

    // Check the status region the failed check writes to
    let status = opening_tag_with(&html, r#"id="attendance-check-status-main""#);
    assert!(status.contains(r#"role="status""#));
    assert!(status.contains(r#"data-attendance-role="check-status""#));
}

#[test]
fn test_page_renders_attendance_checker_hooks() {
    // Render an upcoming event in a non-UTC timezone
    let page = sample_upcoming_page(Los_Angeles);
    let html = page.render().unwrap();

    // Check the enrollment checker request
    let checker = opening_tag_with(&html, r#"data-attendance-role="attendance-checker""#);
    assert!(checker.contains(&format!(
        r#"hx-get="/test-community/event/{}/enrollment""#,
        page.event.event_id
    )));
    assert!(checker.contains(r#"hx-swap="none ignoreTitle:true""#));

    // Check the container exposes the event timezone
    let container = opening_tag_with(&html, "data-attendance-container");
    assert!(container.contains(r#"data-event-timezone="America/Los_Angeles""#));
}

#[test]
fn test_page_renders_attendance_dialogs_hidden_until_opened() {
    // Render an upcoming event that renders every attendance dialog
    let mut page = sample_upcoming_page(chrono_tz::UTC);
    page.event.registration_questions = vec![sample_registration_question()];
    let html = page.render().unwrap();

    // Check every dialog starts hidden from assistive technology
    for id in [
        "questions-modal-main",
        "ticket-modal-main",
        "refund-modal-main",
    ] {
        let dialog = opening_tag_with(&html, &format!(r#"id="{id}""#));
        assert!(dialog.contains(r#"aria-hidden="true""#), "{id}");
    }

    // Check the refund dialog is described by its guidance copy
    let refund_dialog = opening_tag_with(&html, r#"id="refund-modal-main""#);
    assert!(refund_dialog.contains(r#"aria-describedby="refund-modal-description-main""#));
    assert!(html.contains(r#"id="refund-modal-description-main""#));
}

#[test]
fn test_page_renders_attendance_end_time() {
    // Render an upcoming event with an end time
    let ends_at = Utc.with_ymd_and_hms(2099, 6, 1, 20, 0, 0).unwrap();
    let mut page = sample_page(
        Some(Utc.with_ymd_and_hms(2099, 6, 1, 18, 0, 0).unwrap()),
        chrono_tz::UTC,
    );
    page.event.ends_at = Some(ends_at);
    let html = page.render().unwrap();

    // Check the container exposes the end time for the past-event fallback
    let container = opening_tag_with(&html, "data-attendance-container");
    assert!(container.contains(&format!(r#"data-ends="{}""#, ends_at.to_rfc3339())));
}

#[test]
fn test_page_renders_cached_ticket_state() {
    // (case, approval, waitlist enabled, sold out, current price, expected selectable, expected status label)
    let cases = [
        ("sellable", false, false, false, true, true, "Available now"),
        (
            "approval without current price",
            true,
            false,
            false,
            false,
            false,
            "Not on sale",
        ),
        (
            "sold out with waitlist",
            false,
            true,
            true,
            true,
            true,
            "Sold out (you can join the waiting list)",
        ),
        (
            "sold out with approval",
            true,
            true,
            true,
            true,
            true,
            "Sold out",
        ),
    ];

    for (
        case,
        attendee_approval_required,
        waitlist_enabled,
        sold_out,
        current_price,
        expected_selectable,
        expected_status_label,
    ) in cases
    {
        // Render an upcoming event with one ticket type in the case state
        let mut ticket_type = sample_priced_ticket_type(1_500);
        ticket_type.sold_out = sold_out;
        if !current_price {
            ticket_type.current_price = None;
        }
        let mut page = sample_upcoming_page(chrono_tz::UTC);
        page.event.attendee_approval_required = attendee_approval_required;
        page.event.ticket_types = Some(vec![ticket_type]);
        page.event.waitlist_enabled = waitlist_enabled;
        let html = page.render().unwrap();

        // Check the cached radio selectable contract
        let radio = opening_tag_with(&html, r#"id="ticket-type-main-0""#);
        assert!(
            radio.contains(&format!(
                r#"data-ticket-selectable="{expected_selectable}""#
            )),
            "{case}"
        );
        assert_eq!(radio.contains("disabled"), !expected_selectable, "{case}");

        // Check the cached status label
        assert_eq!(
            element_text_with(&html, r#"data-attendance-role="ticket-type-status-label""#),
            expected_status_label,
            "{case}"
        );
    }
}

#[test]
fn test_page_renders_contact_opener_load_error_message() {
    // Render an event without organizers
    let page = sample_upcoming_page(chrono_tz::UTC);
    let html = page.render().unwrap();

    // Check the opener declares the alert shown when the modal fails to load
    let opener = opening_tag_with(&html, r#"id="open-contact-modal""#);
    assert!(opener.contains(
        r#"data-error-message="Something went wrong loading the contact form. Please try again later.""#
    ));
}

#[test]
fn test_page_renders_featured_and_regular_speaker_sections() {
    // Setup a legacy, a featured and a regular speaker
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.legacy_speakers = Some(vec![sample_legacy_user(Some("Legacy Speaker"))]);
    page.event.speakers = vec![
        sample_speaker(
            false,
            sample_named_user(1, "regular-speaker", Some("Regular")),
        ),
        sample_speaker(
            true,
            sample_named_user(2, "featured-speaker", Some("Featured")),
        ),
    ];

    // Render the event page
    let body = page.render().unwrap();

    // Setup the chip needles (names and usernames are HTML-escaped JSON strings inside the
    // user attribute)
    let featured_needle = "&#34;featured-speaker&#34;";
    let legacy_needle = "&#34;Legacy Speaker&#34;";
    let regular_needle = "&#34;regular-speaker&#34;";

    // Check the featured section holds only the featured chip
    let featured_section = element_html_with(&body, "featured-speakers-section");
    let featured_chip = opening_tag_with(featured_section, featured_needle);
    assert!(featured_chip.contains(" featured display-modal"));
    assert!(!featured_section.contains(regular_needle));

    // Check the regular grid lists the legacy chip, as HTML bio, before the regular chip
    let regular_grid = element_html_with(&body, "regular-speakers-grid");
    let legacy_chip = opening_tag_with(regular_grid, legacy_needle);
    let regular_chip = opening_tag_with(regular_grid, regular_needle);
    assert!(legacy_chip.contains(" bio-is-html"));
    assert!(!regular_chip.contains("bio-is-html"));
    assert!(regular_grid.find(legacy_needle).unwrap() < regular_grid.find(regular_needle).unwrap());
    assert!(!regular_grid.contains(featured_needle));
}

#[test]
fn test_page_renders_legacy_host_bio_as_html() {
    // Setup a legacy host and a platform host
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.hosts = vec![sample_named_user(1, "platform-host", Some("Platform Host"))];
    page.event.legacy_hosts = Some(vec![sample_legacy_user(Some("Legacy Host"))]);

    // Render the event page
    let body = page.render().unwrap();

    // Check only the legacy host chip renders its bio as HTML (names and usernames are
    // HTML-escaped JSON strings inside the user attribute)
    let legacy_chip = opening_tag_with(&body, "&#34;Legacy Host&#34;");
    let platform_chip = opening_tag_with(&body, "&#34;platform-host&#34;");
    assert!(legacy_chip.starts_with("<user-chip "));
    assert!(legacy_chip.contains(" bio-is-html"));
    assert!(platform_chip.starts_with("<user-chip "));
    assert!(!platform_chip.contains("bio-is-html"));
}

#[test]
fn test_page_renders_legacy_only_speakers_section() {
    // Setup an event with legacy speakers only
    let mut page = sample_page(None, chrono_tz::UTC);
    page.event.legacy_speakers = Some(vec![sample_legacy_user(Some("Legacy Speaker"))]);

    // Render the event page
    let body = page.render().unwrap();

    // Check the speakers grid lists the legacy chip as HTML bio, without a featured section
    let regular_grid = element_html_with(&body, "regular-speakers-grid");
    let legacy_chip = opening_tag_with(regular_grid, "&#34;Legacy Speaker&#34;");
    assert!(legacy_chip.starts_with("<user-chip "));
    assert!(legacy_chip.contains(" bio-is-html"));
    assert!(!body.contains("featured-speakers-section"));
}

#[test]
fn test_page_renders_multi_day_agenda_as_tabs() {
    // Setup an event with sessions on two days
    let starts_at = Utc.with_ymd_and_hms(2099, 6, 1, 18, 0, 0).unwrap();
    let mut page = sample_page(Some(starts_at), chrono_tz::UTC);
    page.event.sessions = BTreeMap::from([
        (
            starts_at.date_naive(),
            vec![Session {
                name: "Opening keynote".to_string(),
                ..Default::default()
            }],
        ),
        (
            starts_at.date_naive().succ_opt().unwrap(),
            vec![Session {
                name: "Closing panel".to_string(),
                ..Default::default()
            }],
        ),
    ]);

    // Render the event page
    let html = page.render().unwrap();

    // Check the days render as one labelled tablist
    assert_eq!(html.matches(r#"role="tablist""#).count(), 1);
    let tablist = opening_tag_with(&html, r#"role="tablist""#);
    assert!(tablist.contains(r#"aria-label="Agenda days""#));

    // Check only the first day tab is selected and a tab stop
    let first_tab = opening_tag_with(&html, r#"id="agenda-tab-0""#);
    assert!(first_tab.contains(r#"aria-selected="true""#));
    assert!(first_tab.contains(r#"tabindex="0""#));
    let second_tab = opening_tag_with(&html, r#"id="agenda-tab-1""#);
    assert!(second_tab.contains(r#"aria-selected="false""#));
    assert!(second_tab.contains(r#"tabindex="-1""#));
    assert!(second_tab.contains(r#"aria-controls="agenda-panel-1""#));

    // Check the second day panel is linked to its tab and hidden
    let second_panel = opening_tag_with(&html, r#"id="agenda-panel-1""#);
    assert!(second_panel.contains(r#"role="tabpanel""#));
    assert!(second_panel.contains(r#"aria-labelledby="agenda-tab-1""#));
    assert!(
        second_panel
            .trim_end_matches('>')
            .split_whitespace()
            .any(|attribute| attribute == "hidden")
    );
}

#[test]
fn test_page_renders_multi_day_times_with_each_timezone() {
    // Setup a multi-day event spanning the EU daylight saving change
    let mut page = sample_page(
        Some(Utc.with_ymd_and_hms(2030, 3, 30, 17, 0, 0).unwrap()),
        Madrid,
    );
    page.event.ends_at = Some(Utc.with_ymd_and_hms(2030, 3, 31, 18, 0, 0).unwrap());

    // Render the event page
    let body = page.render().unwrap();

    // Check each column shows its own zone abbreviation
    assert!(body.contains("06:00 PM CET"));
    assert!(body.contains("08:00 PM CEST"));
}

#[test]
fn test_page_renders_session_speakers_featured_first() {
    // Setup a session listing a regular, a featured, a nameless and a blank-named speaker
    let starts_at = Utc.with_ymd_and_hms(2099, 6, 1, 18, 0, 0).unwrap();
    let regular = Speaker {
        featured: false,
        user: User {
            username: "regular-speaker".to_string(),
            ..sample_template_user_with_id(Uuid::from_u128(11))
        },
    };
    let featured = Speaker {
        featured: true,
        user: User {
            username: "featured-speaker".to_string(),
            ..sample_template_user_with_id(Uuid::from_u128(12))
        },
    };
    let nameless = Speaker {
        featured: false,
        user: User {
            username: "nameless-speaker".to_string(),
            name: None,
            ..sample_template_user_with_id(Uuid::from_u128(13))
        },
    };
    let blank_named = sample_speaker(false, sample_named_user(14, "blank-speaker", Some("  ")));

    // Render the event page with that session
    let mut page = sample_page(Some(starts_at), chrono_tz::UTC);
    page.event.sessions = BTreeMap::from([(
        starts_at.date_naive(),
        vec![Session {
            name: "Keynote".to_string(),
            speakers: vec![regular, featured, nameless, blank_named],
            starts_at,
            ..Default::default()
        }],
    )]);
    let html = page.render().unwrap();

    // Check featured speakers render first and carry the featured attribute
    // (usernames are HTML-escaped JSON strings inside the user attribute)
    let featured_index = html.find("&#34;featured-speaker&#34;").unwrap();
    let regular_index = html.find("&#34;regular-speaker&#34;").unwrap();
    assert!(featured_index < regular_index);
    assert!(html.contains(" featured small display-modal"));

    // Check speakers without a public name are skipped
    assert!(!html.contains("&#34;nameless-speaker&#34;"));
    assert!(!html.contains("&#34;blank-speaker&#34;"));
}

// Helpers.

/// Returns the value of the named attribute in a rendered opening tag.
fn attribute_value<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let (_, rest) = tag.split_once(&format!(r#" {name}=""#))?;
    rest.split('"').next()
}

/// Returns the bio mode and name of a person listed in a people section.
fn person_summary<'a>(person: &EventPerson<'a>) -> (bool, Option<&'a str>) {
    let name = match *person {
        EventPerson::Legacy(legacy_user) => legacy_user.name.as_deref(),
        EventPerson::User(user) => user.name.as_deref(),
    };
    (person.bio_is_html(), name)
}

fn sample_ticket_type(amount_minor: i64) -> EventTicketType {
    EventTicketType {
        active: true,
        availability: EventTicketTypeAvailability::Public,
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        title: "General admission".to_string(),

        price_windows: vec![EventTicketPriceWindow {
            amount_minor,
            event_ticket_price_window_id: Uuid::new_v4(),

            ends_at: None,
            starts_at: None,
        }],
        ..Default::default()
    }
}

/// Returns the contact context of a viewer allowed to start a conversation.
fn sample_contact_context() -> InboxContactContext {
    InboxContactContext {
        community_name: "test-community".to_string(),
        event_id: Uuid::from_u128(2),
        event_name: "Test Event".to_string(),
        event_slug: "test-event".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "test-group".to_string(),

        group_slug_pretty: None,
        viewer: Some(InboxContactViewer {
            can_manage_inbox: false,
            can_start_conversation: true,
            is_blocked: false,
            is_group_team_member: false,

            open_inbox_conversation_id: None,
        }),
    }
}

/// Returns an imported person with an HTML bio.
fn sample_legacy_user(name: Option<&str>) -> LegacyUser {
    LegacyUser {
        bio: Some("<p>Imported bio</p>".to_string()),
        name: name.map(str::to_string),
        photo_url: None,
        title: None,
    }
}

/// Returns a platform user with a deterministic ID, username and name.
fn sample_named_user(id: u128, username: &str, name: Option<&str>) -> User {
    User {
        username: username.to_string(),
        name: name.map(str::to_string),
        ..sample_template_user_with_id(Uuid::from_u128(id))
    }
}

fn sample_page(starts_at: Option<DateTime<Utc>>, timezone: Tz) -> Page {
    Page {
        base_url: "https://example.test".to_string(),
        event: EventFull {
            community: CommunitySummary {
                display_name: "Test Community".to_string(),
                ..Default::default()
            },
            group: GroupSummary {
                name: "Test Group".to_string(),
                ..Default::default()
            },
            name: "Test Event".to_string(),
            starts_at,
            timezone,
            ..Default::default()
        },
        page_id: PageId::Event,
        path: "/test-community/group/test-group/event/test-event".to_string(),
        site_settings: SiteSettings::default(),
        user: UserMenuState::default(),
    }
}

/// Returns a ticket type whose cached current price matches its open window.
fn sample_priced_ticket_type(amount_minor: i64) -> EventTicketType {
    EventTicketType {
        current_price: Some(EventTicketCurrentPrice {
            amount_minor,
            ..Default::default()
        }),
        ..sample_ticket_type(amount_minor)
    }
}

/// Returns a required free-text registration question.
fn sample_registration_question() -> QuestionnaireQuestion {
    QuestionnaireQuestion {
        id: Uuid::from_u128(1),
        kind: QuestionnaireQuestionKind::FreeText,
        prompt: "Dietary requirements".to_string(),
        required: true,

        options: vec![],
    }
}

/// Returns a speaker for the given user.
fn sample_speaker(featured: bool, user: User) -> Speaker {
    Speaker { featured, user }
}

/// Returns an event page for a fixed 2099 event with registration open.
fn sample_upcoming_page(timezone: Tz) -> Page {
    let mut page = sample_page(
        Some(Utc.with_ymd_and_hms(2099, 6, 1, 18, 0, 0).unwrap()),
        timezone,
    );
    page.event.community.name = "test-community".to_string();
    page.event.event_id = Uuid::from_u128(2);
    page
}
