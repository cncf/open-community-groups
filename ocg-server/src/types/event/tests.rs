use std::collections::BTreeMap;

use chrono::{Duration, TimeZone, Utc};

use crate::types::payments::{EventTicketCurrentPrice, EventTicketType};

use super::*;

#[test]
fn event_attendance_info_can_request_refund_allows_tbd_events() {
    let attendance = EventAttendanceInfo {
        is_checked_in: false,
        manually_invited: false,
        status: EventAttendanceStatus::Attendee,

        purchase_amount_minor: Some(2_500),
        refund_request_status: None,
        resume_checkout_url: None,
    };

    assert!(attendance.can_request_refund(Some(Utc::now() + Duration::hours(1))));
    assert!(attendance.can_request_refund(None));
    assert!(!attendance.can_request_refund(Some(Utc::now() - Duration::hours(1))));
}

#[test]
fn event_full_to_summary_maps_event_fields() {
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_series_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let starts_at = Utc.with_ymd_and_hms(2030, 1, 2, 3, 4, 5).unwrap();
    let ends_at = starts_at + Duration::hours(2);
    let registration_starts_at = starts_at - Duration::days(14);
    let registration_ends_at = starts_at - Duration::hours(1);
    let event = EventFull {
        canceled: true,
        community: CommunitySummary {
            community_id,
            display_name: "Community Display".to_string(),
            name: "community".to_string(),
            ..Default::default()
        },
        description_short: Some("Short description".to_string()),
        ends_at: Some(ends_at),
        event_id,
        event_series_id: Some(event_series_id),
        group: GroupSummary {
            category: crate::types::group::GroupCategory {
                name: "Technology".to_string(),
                ..Default::default()
            },
            group_id,
            name: "Group Name".to_string(),
            slug: "group-slug".to_string(),

            slug_pretty: Some("pretty-group-slug".to_string()),
            ..Default::default()
        },
        has_related_events: true,
        kind: EventKind::Hybrid,
        logo_url: "https://example.com/logo.png".to_string(),
        name: "Event Name".to_string(),
        payment_currency_code: Some("USD".to_string()),
        published: true,
        registration_ends_at: Some(registration_ends_at),
        registration_starts_at: Some(registration_starts_at),
        remaining_capacity: Some(7),
        slug: "event-slug".to_string(),
        starts_at: Some(starts_at),
        test_event: true,
        timezone: chrono_tz::Europe::Madrid,
        venue_city: Some("Madrid".to_string()),
        waitlist_count: 3,
        waitlist_enabled: true,
        ..Default::default()
    };
    let summary = EventSummary::from(&event);

    assert!(summary.canceled);
    assert_eq!(summary.community_display_name, "Community Display");
    assert_eq!(summary.community_name, "community");
    assert_eq!(
        summary.description_short.as_deref(),
        Some("Short description")
    );
    assert_eq!(summary.ends_at, Some(ends_at));
    assert_eq!(summary.event_id, event_id);
    assert_eq!(summary.event_series_id, Some(event_series_id));
    assert_eq!(summary.group_category_name, "Technology");
    assert_eq!(summary.group_name, "Group Name");
    assert_eq!(summary.group_slug, "group-slug");
    assert_eq!(
        summary.group_slug_pretty.as_deref(),
        Some("pretty-group-slug")
    );
    assert!(summary.has_related_events);
    assert_eq!(summary.kind, EventKind::Hybrid);
    assert_eq!(summary.logo_url, "https://example.com/logo.png");
    assert_eq!(summary.name, "Event Name");
    assert_eq!(summary.payment_currency_code.as_deref(), Some("USD"));
    assert_eq!(summary.popover_html, None);
    assert!(summary.published);
    assert_eq!(summary.registration_ends_at, Some(registration_ends_at));
    assert_eq!(summary.registration_starts_at, Some(registration_starts_at));
    assert_eq!(summary.remaining_capacity, Some(7));
    assert_eq!(summary.slug, "event-slug");
    assert_eq!(summary.starts_at, Some(starts_at));
    assert!(summary.test_event);
    assert_eq!(summary.timezone, chrono_tz::Europe::Madrid);
    assert_eq!(summary.venue_city.as_deref(), Some("Madrid"));
    assert_eq!(summary.waitlist_count, 3);
    assert!(summary.waitlist_enabled);
}

#[test]
fn event_full_cfs_is_enabled_returns_false_when_flag_missing() {
    let event = EventFull {
        cfs_enabled: None,
        ..Default::default()
    };
    assert!(!event.cfs_is_enabled());
}

#[test]
fn event_full_cfs_is_enabled_returns_true_when_flag_set() {
    let event = EventFull {
        cfs_enabled: Some(true),
        ..Default::default()
    };
    assert!(event.cfs_is_enabled());
}

#[test]
fn event_full_cfs_is_open_returns_false_when_disabled() {
    let now = Utc::now();
    let event = EventFull {
        cfs_enabled: Some(false),
        cfs_starts_at: Some(now - Duration::hours(1)),
        cfs_ends_at: Some(now + Duration::hours(1)),
        ..Default::default()
    };
    assert!(!event.cfs_is_open());
}

#[test]
fn event_full_cfs_is_open_returns_true_when_within_window() {
    let now = Utc::now();
    let event = EventFull {
        cfs_enabled: Some(true),
        cfs_starts_at: Some(now - Duration::hours(1)),
        cfs_ends_at: Some(now + Duration::hours(1)),
        ..Default::default()
    };
    assert!(event.cfs_is_open());
}

#[test]
fn event_full_cfs_is_closed_returns_true_when_window_ended() {
    let event = EventFull {
        cfs_enabled: Some(true),
        cfs_ends_at: Some(Utc::now() - Duration::hours(1)),
        ..Default::default()
    };
    assert!(event.cfs_is_closed());
}

#[test]
fn event_full_cfs_is_upcoming_returns_false_when_started() {
    let event = EventFull {
        cfs_enabled: Some(true),
        cfs_starts_at: Some(Utc::now() - Duration::hours(1)),
        ..Default::default()
    };
    assert!(!event.cfs_is_upcoming());
}

#[test]
fn event_full_cfs_is_upcoming_returns_true_when_start_in_future() {
    let event = EventFull {
        cfs_enabled: Some(true),
        cfs_starts_at: Some(Utc::now() + Duration::hours(1)),
        ..Default::default()
    };
    assert!(event.cfs_is_upcoming());
}

#[test]
fn event_full_has_sellable_ticket_types_returns_false_when_no_tier_is_purchasable() {
    let event = EventFull {
        ticket_types: Some(vec![
            sample_ticket_type(false, Some(0), false, "Hidden free"),
            sample_ticket_type(true, None, false, "No current price"),
            sample_ticket_type(true, Some(1500), true, "Sold out"),
        ]),
        ..Default::default()
    };

    assert!(!event.has_sellable_ticket_types());
    assert!(event.is_ticketed());
}

#[test]
fn event_full_is_live_returns_false_when_ends_at_is_none() {
    let event = EventFull {
        starts_at: Some(Utc::now() - Duration::hours(1)),
        ends_at: None,
        ..Default::default()
    };
    assert!(!event.is_live());
}

#[test]
fn event_full_is_live_returns_false_when_event_ended() {
    let event = EventFull {
        starts_at: Some(Utc::now() - Duration::hours(2)),
        ends_at: Some(Utc::now() - Duration::hours(1)),
        ..Default::default()
    };
    assert!(!event.is_live());
}

#[test]
fn event_full_is_live_returns_false_when_event_not_started() {
    let event = EventFull {
        starts_at: Some(Utc::now() + Duration::hours(1)),
        ends_at: Some(Utc::now() + Duration::hours(2)),
        ..Default::default()
    };
    assert!(!event.is_live());
}

#[test]
fn event_full_is_live_returns_false_when_starts_at_is_none() {
    let event = EventFull {
        starts_at: None,
        ends_at: Some(Utc::now() + Duration::hours(1)),
        ..Default::default()
    };
    assert!(!event.is_live());
}

#[test]
fn event_full_is_live_returns_true_when_event_is_live() {
    let event = EventFull {
        starts_at: Some(Utc::now() - Duration::hours(1)),
        ends_at: Some(Utc::now() + Duration::hours(1)),
        ..Default::default()
    };
    assert!(event.is_live());
}

#[test]
fn event_full_is_live_returns_true_when_event_starts_soon() {
    let event = EventFull {
        starts_at: Some(Utc::now() + Duration::minutes(10)),
        ends_at: Some(Utc::now() + Duration::hours(1)),
        ..Default::default()
    };
    assert!(event.is_live());
}

#[test]
fn event_full_is_past_returns_false_when_both_times_are_none() {
    let event = EventFull {
        ends_at: None,
        starts_at: None,
        ..Default::default()
    };
    assert!(!event.is_past());
}

#[test]
fn event_full_is_past_returns_false_when_ends_at_is_in_future() {
    let event = EventFull {
        ends_at: Some(Utc::now() + Duration::hours(1)),
        starts_at: Some(Utc::now() - Duration::hours(1)),
        ..Default::default()
    };
    assert!(!event.is_past());
}

#[test]
fn event_full_is_past_returns_false_when_starts_at_is_in_future() {
    let event = EventFull {
        ends_at: None,
        starts_at: Some(Utc::now() + Duration::hours(1)),
        ..Default::default()
    };
    assert!(!event.is_past());
}

#[test]
fn event_full_is_past_returns_true_when_ends_at_is_in_past() {
    let event = EventFull {
        ends_at: Some(Utc::now() - Duration::hours(1)),
        starts_at: Some(Utc::now() - Duration::hours(2)),
        ..Default::default()
    };
    assert!(event.is_past());
}

#[test]
fn event_full_is_past_returns_true_when_starts_at_is_in_past_and_no_ends_at() {
    let event = EventFull {
        ends_at: None,
        starts_at: Some(Utc::now() - Duration::hours(1)),
        ..Default::default()
    };
    assert!(event.is_past());
}

#[test]
fn event_full_speakers_ids_collects_both_event_and_session_level_speakers() {
    let event_speaker_id = Uuid::from_u128(1);
    let session_speaker_id = Uuid::from_u128(2);
    let date = Utc::now().date_naive();

    let event = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: User {
                user_id: event_speaker_id,
                ..Default::default()
            },
        }],
        sessions: BTreeMap::from([(
            date,
            vec![Session {
                speakers: vec![Speaker {
                    featured: false,
                    user: User {
                        user_id: session_speaker_id,
                        ..Default::default()
                    },
                }],
                starts_at: Utc::now(),
                ..Default::default()
            }],
        )]),
        ..Default::default()
    };

    let ids = event.speakers_ids();
    assert_eq!(ids.len(), 2);
    assert!(ids.contains(&event_speaker_id));
    assert!(ids.contains(&session_speaker_id));
}

#[test]
fn event_full_speakers_ids_deduplicates_speakers() {
    let shared_speaker_id = Uuid::from_u128(1);
    let date = Utc::now().date_naive();

    // Same speaker appears at both event and session level
    let event = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: User {
                user_id: shared_speaker_id,
                ..Default::default()
            },
        }],
        sessions: BTreeMap::from([(
            date,
            vec![Session {
                speakers: vec![Speaker {
                    featured: false,
                    user: User {
                        user_id: shared_speaker_id,
                        ..Default::default()
                    },
                }],
                starts_at: Utc::now(),
                ..Default::default()
            }],
        )]),
        ..Default::default()
    };

    let ids = event.speakers_ids();
    assert_eq!(ids.len(), 1);
    assert_eq!(ids[0], shared_speaker_id);
}

#[test]
fn event_full_speakers_ids_returns_empty_when_no_speakers() {
    let event = EventFull::default();
    assert!(event.speakers_ids().is_empty());
}

#[test]
fn event_full_speakers_ids_returns_sorted_ids() {
    let id_a = Uuid::from_u128(100);
    let id_b = Uuid::from_u128(50);
    let id_c = Uuid::from_u128(200);

    let event = EventFull {
        speakers: vec![
            Speaker {
                featured: false,
                user: User {
                    user_id: id_a,
                    ..Default::default()
                },
            },
            Speaker {
                featured: false,
                user: User {
                    user_id: id_b,
                    ..Default::default()
                },
            },
            Speaker {
                featured: false,
                user: User {
                    user_id: id_c,
                    ..Default::default()
                },
            },
        ],
        ..Default::default()
    };

    let ids = event.speakers_ids();
    assert_eq!(ids, vec![id_b, id_a, id_c]); // Sorted by UUID value
}

#[test]
fn event_full_sellable_ticket_types_filters_unsellable_tiers() {
    let event = EventFull {
        ticket_types: Some(vec![
            sample_ticket_type(false, Some(0), false, "Hidden free"),
            sample_ticket_type(true, None, false, "No current price"),
            sample_ticket_type(true, Some(1500), true, "Sold out"),
            sample_ticket_type(true, Some(2500), false, "General"),
        ]),
        ..Default::default()
    };

    let ticket_titles: Vec<_> = event
        .sellable_ticket_types()
        .into_iter()
        .map(|ticket_type| ticket_type.title.as_str())
        .collect();

    assert_eq!(ticket_titles, vec!["General"]);
}

#[test]
fn event_full_unconfigured_registration_window_stays_open_after_event_start() {
    let now = Utc::now();
    let event = EventFull {
        ends_at: Some(now + Duration::hours(1)),
        registration_ends_at: None,
        registration_starts_at: None,
        starts_at: Some(now - Duration::hours(1)),
        timezone: chrono_tz::UTC,
        ..Default::default()
    };

    assert!(event.registration_window_is_open());
    assert_eq!(event.registration_window_message(), None);
    assert_eq!(event.registration_window_unavailable_title(), None);
}

#[test]
fn event_full_visible_ticket_types_include_sold_out_tiers_sorted_by_price() {
    let event = EventFull {
        ticket_types: Some(vec![
            sample_ticket_type(false, Some(500), false, "Inactive cheap"),
            sample_ticket_type(true, None, false, "No current price"),
            sample_ticket_type(true, Some(3000), false, "General"),
            sample_ticket_type(true, Some(1500), true, "Sold out"),
            sample_ticket_type(true, Some(2000), false, "Regular"),
        ]),
        ..Default::default()
    };

    let ticket_titles: Vec<_> = event
        .visible_ticket_types()
        .into_iter()
        .map(|ticket_type| ticket_type.title.as_str())
        .collect();

    assert_eq!(ticket_titles, vec!["Sold out", "Regular", "General"]);
}

#[test]
fn event_summary_registration_window_closes_open_only_window_at_event_start() {
    let now = Utc::now();
    let mut event = sample_event_summary(vec![]);
    event.ends_at = Some(now + Duration::hours(1));
    event.registration_ends_at = None;
    event.registration_starts_at = Some(now - Duration::hours(2));
    event.starts_at = Some(now - Duration::hours(1));
    event.timezone = chrono_tz::UTC;

    assert!(!event.registration_window_is_open());
    assert!(
        event
            .registration_window_message()
            .is_some_and(|message| message.starts_with("Registration closed "))
    );
    assert!(
        event
            .registration_window_unavailable_title()
            .is_some_and(|message| message.starts_with("Registration closed "))
    );
}

#[test]
fn event_summary_formatted_ticket_price_badge_ignores_unsellable_tiers() {
    let event = sample_event_summary(vec![
        sample_ticket_type(false, Some(0), false, "Inactive free"),
        sample_ticket_type(true, Some(1000), true, "Sold out early bird"),
        sample_ticket_type(true, Some(2500), false, "General"),
    ]);

    assert_eq!(
        event.formatted_ticket_price_badge(),
        Some("From USD 25.00".to_string())
    );
}

#[test]
fn event_summary_formatted_ticket_price_badge_returns_free_and_up_when_mixed() {
    let event = sample_event_summary(vec![
        sample_ticket_type(true, Some(0), false, "Free"),
        sample_ticket_type(true, Some(2500), false, "General"),
    ]);

    assert_eq!(
        event.formatted_ticket_price_badge(),
        Some("Free and up".to_string())
    );
}

// Helpers.

/// Build a sample ticket type with specified properties for testing.
fn sample_ticket_type(
    active: bool,
    amount_minor: Option<i64>,
    sold_out: bool,
    title: &str,
) -> EventTicketType {
    EventTicketType {
        active,
        event_ticket_type_id: Uuid::nil(),
        order: 1,
        title: title.to_string(),

        current_price: amount_minor.map(|amount_minor| EventTicketCurrentPrice {
            amount_minor,
            ..Default::default()
        }),
        description: None,
        price_windows: vec![],
        remaining_seats: None,
        seats_total: None,
        sold_out,
    }
}

/// Build a sample event summary with specified ticket types for testing.
fn sample_event_summary(ticket_types: Vec<EventTicketType>) -> EventSummary {
    EventSummary {
        attendee_approval_required: false,
        canceled: false,
        community_display_name: "Community".to_string(),
        community_name: "community".to_string(),
        event_id: Uuid::nil(),
        group_category_name: "Technology".to_string(),
        group_name: "Group".to_string(),
        group_slug: "group".to_string(),
        has_registration_questions: false,
        has_related_events: false,
        kind: EventKind::InPerson,
        logo_url: "https://example.com/logo.png".to_string(),
        name: "Event".to_string(),
        payment_currency_code: Some("USD".to_string()),
        published: true,
        registration_ends_at: None,
        registration_starts_at: None,
        slug: "event".to_string(),
        test_event: false,
        ticket_types: Some(ticket_types),
        timezone: chrono_tz::UTC,
        waitlist_count: 0,
        waitlist_enabled: false,

        capacity: None,
        created_by_display_name: None,
        created_by_username: None,
        description_short: None,
        ends_at: None,
        event_series_id: None,
        group_slug_pretty: None,
        latitude: None,
        longitude: None,
        meeting_join_instructions: None,
        meeting_join_url: None,
        meeting_password: None,
        meeting_provider: None,
        popover_html: None,
        remaining_capacity: None,
        starts_at: None,
        venue_address: None,
        venue_city: None,
        venue_country_code: None,
        venue_country_name: None,
        venue_name: None,
        venue_state: None,
        zip_code: None,
    }
}
