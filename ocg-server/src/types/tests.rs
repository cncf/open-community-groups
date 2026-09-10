//! Shared sample data builders for domain types, used by tests across layers.

use std::collections::BTreeMap;

use chrono::{Duration, TimeZone, Utc};
use chrono_tz::UTC;
use uuid::Uuid;

use crate::types::{
    community::CommunitySummary,
    dashboard::group::events::EventInput,
    event::{EventFull, EventKind, EventSummary},
    group::{GroupCategory, GroupRegion, GroupSummary},
    payments::{GroupPaymentRecipient, PaymentProvider},
    site::{SiteSettings, Theme},
    user::User,
};

/// Sample community summary used across tests.
pub(crate) fn sample_community_summary(community_id: Uuid) -> CommunitySummary {
    CommunitySummary {
        banner_mobile_url: "https://example.test/banner_mobile.png".to_string(),
        banner_url: "https://example.test/banner.png".to_string(),
        community_id,
        display_name: "Test".to_string(),
        logo_url: "/static/images/placeholder_cncf.png".to_string(),
        name: "test".to_string(),
        ad_banner_link_url: None,
        ad_banner_url: None,
        og_image_url: None,
    }
}

/// Sample event form payload submitted from the dashboard.
pub(crate) fn sample_event_form() -> EventInput {
    EventInput {
        category_id: Uuid::new_v4(),
        description: "Event description".to_string(),
        kind_id: "virtual".to_string(),
        name: "Sample Event".to_string(),
        timezone: "UTC".to_string(),

        banner_url: Some("https://example.test/banner.png".to_string()),
        capacity: Some(100),
        description_short: Some("Short".to_string()),
        waitlist_enabled: Some(false),
        ..Default::default()
    }
}

/// Sample full event with hosts, sponsors, and schedule.
pub(crate) fn sample_event_full(community_id: Uuid, event_id: Uuid, group_id: Uuid) -> EventFull {
    let starts_at = Utc::now() + Duration::hours(1);
    let mut sessions = BTreeMap::new();
    sessions.insert(starts_at.date_naive(), Vec::new());

    EventFull {
        canceled: false,
        category_name: "Cloud Native".to_string(),
        community: sample_community_summary(community_id),
        created_at: Utc::now(),
        description: "A detailed event description".to_string(),
        event_id,
        group: sample_group_summary(group_id),
        hosts: vec![sample_template_user()],
        kind: EventKind::InPerson,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Test Event".to_string(),
        organizers: vec![sample_template_user()],
        published: true,
        sessions,
        slug: "abc1234".to_string(),
        timezone: UTC,

        banner_url: Some("https://example.test/banner.png".to_string()),
        capacity: Some(100),
        description_short: Some("A test event".to_string()),
        ends_at: Some(starts_at + Duration::hours(1)),
        latitude: Some(37.0),
        longitude: Some(-122.0),
        starts_at: Some(starts_at),
        venue_address: Some("123 Main St".to_string()),
        venue_city: Some("San Francisco".to_string()),
        venue_country_code: Some("US".to_string()),
        venue_country_name: Some("United States".to_string()),
        venue_name: Some("Main Venue".to_string()),
        venue_state_code: Some("CA".to_string()),
        venue_state_name: Some("California".to_string()),
        waitlist_count: 0,
        waitlist_enabled: false,
        ..Default::default()
    }
}

/// Sample event summary used in listings.
pub(crate) fn sample_event_summary(event_id: Uuid, _group_id: Uuid) -> EventSummary {
    let starts_at = Utc::now() + Duration::hours(1);
    EventSummary {
        attendee_approval_required: false,
        canceled: false,
        community_display_name: "Test Community".to_string(),
        community_name: "test-community".to_string(),
        event_id,
        group_category_name: "Meetup".to_string(),
        group_name: "Test Group".to_string(),
        group_slug: "def5678".to_string(),
        has_external_payment: false,
        has_registration_questions: false,
        has_related_events: false,
        kind: EventKind::Virtual,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Sample Event".to_string(),
        published: true,
        slug: "ghi9abc".to_string(),
        test_event: false,
        timezone: UTC,

        attendee_count: None,
        capacity: None,
        created_by_display_name: None,
        created_by_username: None,
        delete_eligibility: None,
        description_short: Some("A brief summary of the sample event".to_string()),
        ends_at: Some(starts_at + Duration::hours(2)),
        event_series_id: None,
        group_slug_pretty: None,
        latitude: Some(42.3601),
        longitude: Some(-71.0589),
        meeting_join_instructions: None,
        meeting_join_url: Some("https://example.test/meeting".to_string()),
        meeting_password: None,
        meeting_provider: None,
        payment_currency_code: None,
        popover_html: None,
        registration_ends_at: None,
        registration_starts_at: None,
        remaining_capacity: None,
        starts_at: Some(starts_at),
        ticket_types: None,
        venue_address: Some("456 Sample Rd".to_string()),
        venue_city: Some("Boston".to_string()),
        venue_country_code: Some("US".to_string()),
        venue_country_name: Some("United States".to_string()),
        venue_name: Some("Sample Venue".to_string()),
        venue_state_code: Some("MA".to_string()),
        venue_state_name: Some("Massachusetts".to_string()),
        waitlist_count: 0,
        waitlist_enabled: false,
        zip_code: Some("02101".to_string()),
    }
}

/// Sample group category reused across tests.
pub(crate) fn sample_group_category() -> GroupCategory {
    GroupCategory {
        groups_count: Some(0),
        group_category_id: Uuid::new_v4(),
        name: "Meetup".to_string(),
        normalized_name: "meetup".to_string(),
        order: Some(1),
    }
}

/// Sample Stripe payment recipient used in group dashboard tests.
pub(crate) fn sample_group_payment_recipient() -> GroupPaymentRecipient {
    GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: "acct_test".to_string(),
        seller_display_name: "Test Fiscal Sponsor".to_string(),
    }
}

/// Sample group region definition reused across tests.
pub(crate) fn sample_group_region() -> GroupRegion {
    GroupRegion {
        name: "North America".to_string(),
        normalized_name: "north-america".to_string(),
        region_id: Uuid::new_v4(),

        groups_count: Some(0),
        order: Some(1),
    }
}

/// Sample group summary used by multiple fixtures.
pub(crate) fn sample_group_summary(group_id: Uuid) -> GroupSummary {
    GroupSummary {
        active: true,
        category: sample_group_category(),
        community_display_name: "Test Community".to_string(),
        community_name: "test-community".to_string(),
        created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        group_id,
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Test Group".to_string(),
        slug: "npq6789".to_string(),

        banner_mobile_url: Some("https://example.test/banner_mobile.png".to_string()),
        banner_url: Some("https://example.test/banner.png".to_string()),
        city: Some("San Francisco".to_string()),
        country_code: Some("US".to_string()),
        country_name: Some("United States".to_string()),
        description_short: Some("An example summary for the sample group".to_string()),
        latitude: Some(37.0),
        longitude: Some(-122.0),
        og_image_url: None,
        popover_html: None,
        region: Some(sample_group_region()),
        slug_pretty: None,
        state: Some("CA".to_string()),
    }
}

/// Sample paid event payload for dashboard group event form tests.
pub(crate) fn sample_paid_event_body() -> String {
    let event_form = sample_event_form();

    format!(
        concat!(
            "{}",
            "&payment_currency_code=USD",
            "&ticket_types_present=true",
            "&ticket_types[0][active]=true",
            "&ticket_types[0][order]=1",
            "&ticket_types[0][price_windows][0][amount_minor]=1500",
            "&ticket_types[0][seats_total]=25",
            "&ticket_types[0][title]=General%20admission"
        ),
        serde_qs::to_string(&event_form).unwrap(),
    )
}

/// Sample site settings used across tests.
pub(crate) fn sample_site_settings() -> SiteSettings {
    SiteSettings {
        description: "Test site".to_string(),
        site_id: Uuid::new_v4(),
        theme: Theme {
            palette: BTreeMap::new(),
            primary_color: "#000000".to_string(),
        },
        title: "Test Site".to_string(),
        ..Default::default()
    }
}

/// Sample template user used in event fixtures.
pub(crate) fn sample_template_user() -> User {
    User {
        user_id: Uuid::new_v4(),
        username: "organizer".to_string(),

        name: Some("Organizer".to_string()),
        ..Default::default()
    }
}

/// Sample template user with a specific user ID.
pub(crate) fn sample_template_user_with_id(user_id: Uuid) -> User {
    User {
        user_id,
        username: "speaker".to_string(),

        name: Some("Speaker".to_string()),
        ..Default::default()
    }
}
