//! Shared sample data builders for domain types, used by tests across layers.

use std::collections::BTreeMap;

use chrono::{Duration, NaiveDate, TimeZone, Utc};
use chrono_tz::UTC;
use uuid::Uuid;

use crate::types::{
    community::CommunitySummary,
    dashboard::group::{
        event_analytics::{
            EventAdmissionOfferCount, EventAdmissionOfferOutcome, EventAnalytics,
            EventAnalyticsContext, EventAnalyticsMarker, EventAnalyticsMarkerKind,
            EventAnalyticsRange, EventAudienceStats, EventCheckInStats, EventDiscountCodeUsage,
            EventEnrollmentStats, EventInvitationRequestCounts, EventRegistrationPathCounts,
            EventRegistrationsDailySeries, EventSurveyResponseStats, EventSurveysStats,
            EventTicketTypeUsage, EventTicketsStats, EventTrafficStats, EventUtmCombination,
            EventUtmDimension, EventUtmStats, EventUtmValue, EventViewsDailySeries,
            RegistrationSeriesKind, ViewsSeriesKind,
        },
        events::EventInput,
        surveys::{EventSurveyFull, EventSurveySummary},
    },
    dashboard::user::events::{UserEventSurvey, UserEventSurveyItem},
    event::{
        EventAdmissionOfferSource, EventCohostGroup, EventFull, EventKind, EventMinimal,
        EventSummary,
    },
    event_survey::{EventSurveyAudience, EventSurveyState},
    group::{GroupCategory, GroupMinimal, GroupRegion, GroupSummary},
    inbox::{
        InboxConversation, InboxConversationStatus, InboxConversationSummary, InboxEvent,
        InboxMessage, InboxMessageKind,
    },
    payments::{GroupPaymentRecipient, PaymentProvider},
    questionnaire::{
        QuestionnaireOption, QuestionnaireOptionCount, QuestionnaireQuestion,
        QuestionnaireQuestionBreakdown, QuestionnaireQuestionKind,
    },
    site::{SiteSettings, Theme},
    user::{User, UserSearchResult},
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

/// Sample analytics of a past paid event used across tests.
#[allow(clippy::too_many_lines)]
pub(crate) fn sample_event_analytics() -> EventAnalytics {
    let day_series = |counts: [i64; 3]| {
        ["2024-03-08", "2024-03-09", "2024-03-10"]
            .into_iter()
            .zip(counts)
            .map(|(day, count)| (day.to_string(), count))
            .collect::<Vec<_>>()
    };

    EventAnalytics {
        audience: EventAudienceStats {
            questions: vec![QuestionnaireQuestionBreakdown {
                kind: QuestionnaireQuestionKind::SingleSelect,
                options: vec![QuestionnaireOptionCount {
                    count: 3,
                    label: "Developer".to_string(),
                    option_id: Uuid::from_u128(11),
                }],
                position: 1,
                prompt: "Role".to_string(),
                question_id: Uuid::from_u128(10),
                respondents: 3,
                selections: 3,
            }],
            window_end_capped: false,
            window_end_inferred: true,
            window_start_inferred: true,

            members_joined_in_window: Some(4),
            members_joined_in_window_registered: Some(2),
            new_attendees: Some(3),
            returning_attendees: Some(1),
            window_ends_at: Some(Utc.with_ymd_and_hms(2024, 3, 10, 19, 0, 0).unwrap()),
            window_starts_at: Some(Utc.with_ymd_and_hms(2024, 3, 8, 10, 0, 0).unwrap()),
        },
        check_ins: EventCheckInStats {
            bin_minutes: 15,
            bins: vec![(1_710_087_300_000, 1), (1_710_088_200_000, 2)],
            outside_range: 0,
        },
        enrollment: EventEnrollmentStats {
            admission_offers: vec![EventAdmissionOfferCount {
                count: 1,
                outcome: EventAdmissionOfferOutcome::DeadlinePassed,
                source: EventAdmissionOfferSource::Waitlist,
            }],
            cancellations: 1,
            checked_in: 3,
            invitation_requests: EventInvitationRequestCounts {
                accepted: 1,
                pending: 0,
                rejected: 0,
            },
            registrations: 4,
            registrations_by_path: EventRegistrationPathCounts {
                approval: 0,
                direct: 3,
                organizer_invitation: 0,
                unknown: 0,
                waitlist: 1,
            },
            waitlist: 2,
        },
        event: EventAnalyticsContext {
            canceled: false,
            is_paid: true,
            published: true,
            timezone: chrono_tz::Europe::Madrid,

            capacity: Some(10),
            ends_at: Some(Utc.with_ymd_and_hms(2024, 3, 10, 19, 0, 0).unwrap()),
            published_at: Some(Utc.with_ymd_and_hms(2024, 3, 8, 10, 0, 0).unwrap()),
            registration_ends_at: None,
            registration_starts_at: None,
            starts_at: Some(Utc.with_ymd_and_hms(2024, 3, 10, 17, 0, 0).unwrap()),
        },
        markers: vec![EventAnalyticsMarker {
            kind: EventAnalyticsMarkerKind::Published,
            ts: Utc.with_ymd_and_hms(2024, 3, 8, 10, 0, 0).unwrap(),
        }],
        markers_announcements_omitted: 0,
        surveys: EventSurveysStats {
            surveys: vec![EventSurveyResponseStats {
                eligible_count: 4,
                eligible_respondents_count: 3,
                event_survey_id: Uuid::from_u128(30),
                responses_count: 3,
                state: EventSurveyState::Closed,
                title: "Feedback".to_string(),
            }],
            total_eligible_count: 4,
            total_eligible_respondents_count: 3,
        },
        traffic: EventTrafficStats {
            attribution_consistent: true,
            registrations_baseline: 0,
            registrations_by_ticket_type_per_day: vec![EventRegistrationsDailySeries {
                kind: RegistrationSeriesKind::TicketType,
                series: day_series([1, 2, 1]),

                event_ticket_type_id: Some(Uuid::from_u128(20)),
                order: Some(1),
                title: Some("General".to_string()),
            }],
            registrations_running_total: day_series([1, 3, 4]),
            views_after_end: 3,
            views_before_start: 2,
            views_by_source_per_day: vec![
                EventViewsDailySeries {
                    kind: ViewsSeriesKind::Source,
                    series: day_series([4, 0, 0]),

                    source: Some("newsletter".to_string()),
                },
                EventViewsDailySeries {
                    kind: ViewsSeriesKind::Untagged,
                    series: day_series([6, 5, 0]),

                    source: None,
                },
            ],
            views_total: 20,
        },
        utm: EventUtmStats {
            by_campaign: EventUtmDimension {
                not_specified: 4,
                remainder_count: 0,
                remainder_views: 0,
                values: vec![],
            },
            by_medium: EventUtmDimension {
                not_specified: 0,
                remainder_count: 0,
                remainder_views: 0,
                values: vec![EventUtmValue {
                    value: "email".to_string(),
                    views: 4,
                }],
            },
            by_source: EventUtmDimension {
                not_specified: 0,
                remainder_count: 0,
                remainder_views: 0,
                values: vec![EventUtmValue {
                    value: "newsletter".to_string(),
                    views: 4,
                }],
            },
            combinations: vec![EventUtmCombination {
                first_day: NaiveDate::from_ymd_opt(2024, 3, 8).unwrap(),
                last_day: NaiveDate::from_ymd_opt(2024, 3, 8).unwrap(),
                views: 4,

                utm_campaign: None,
                utm_medium: Some("email".to_string()),
                utm_source: Some("newsletter".to_string()),
            }],
            combinations_remainder_views: 0,
            combinations_total_count: 1,
            tagged_views: 4,
        },

        range: Some(EventAnalyticsRange {
            end_day: NaiveDate::from_ymd_opt(2024, 3, 10).unwrap(),
            start_day: NaiveDate::from_ymd_opt(2024, 3, 8).unwrap(),
        }),
        tickets: Some(EventTicketsStats {
            discount_codes: vec![EventDiscountCodeUsage {
                active: true,
                code: "SAVE10".to_string(),
                event_discount_code_id: Uuid::from_u128(30),
                redemptions: 2,
                title: "Save ten".to_string(),

                available: Some(8),
                total_available: Some(10),
            }],
            ticket_types: vec![EventTicketTypeUsage {
                active: true,
                allocated: 5,
                event_ticket_type_id: Uuid::from_u128(20),
                order: 1,
                remaining: 5,
                seats_total: 10,
                sold: 4,
                title: "General".to_string(),
            }],
        }),
    }
}

/// Sample group credited as an event co-host.
pub(crate) fn sample_event_cohost_group(group_id: Uuid, name: &str) -> EventCohostGroup {
    EventCohostGroup {
        community_display_name: "Cohost Community".to_string(),
        community_name: "cohost-community".to_string(),
        group_id,
        logo_url: "https://example.test/cohost.png".to_string(),
        name: name.to_string(),
        slug: format!("cohost-{}", &group_id.simple().to_string()[..7]),

        slug_pretty: None,
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

/// Sample minimal event drawn on the explore map and calendar.
pub(crate) fn sample_event_minimal(event_id: Uuid) -> EventMinimal {
    let starts_at = Utc.with_ymd_and_hms(2030, 1, 10, 18, 0, 0).unwrap();
    EventMinimal {
        community_name: "test-community".to_string(),
        event_id,
        group_slug: "def5678".to_string(),
        name: "Sample Minimal Event".to_string(),
        slug: "ghi9abc".to_string(),

        ends_at: Some(starts_at + Duration::hours(2)),
        group_slug_pretty: None,
        latitude: Some(42.3601),
        longitude: Some(-71.0589),
        starts_at: Some(starts_at),
    }
}

/// Sample event summary used in listings.
pub(crate) fn sample_event_summary(event_id: Uuid, _group_id: Uuid) -> EventSummary {
    let starts_at = Utc::now() + Duration::hours(1);
    EventSummary {
        attendee_approval_required: false,
        canceled: false,
        cohosts: vec![],
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
        pending_cohosts_count: None,
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

/// Sample event survey with one free-text and one single-select question.
pub(crate) fn sample_event_survey_full(event_survey_id: Uuid) -> EventSurveyFull {
    EventSurveyFull {
        created_at: Utc.with_ymd_and_hms(2099, 5, 1, 9, 0, 0).unwrap(),
        questions: vec![
            sample_survey_question(Uuid::from_u128(0x5d01)),
            QuestionnaireQuestion {
                id: Uuid::from_u128(0x5d02),
                kind: QuestionnaireQuestionKind::SingleSelect,
                prompt: "How would you rate the sessions?".to_string(),
                required: true,

                options: vec![QuestionnaireOption {
                    id: Uuid::from_u128(0x5e01),
                    label: "Excellent".to_string(),
                }],
            },
        ],
        summary: EventSurveySummary {
            questions_count: 2,
            ..sample_event_survey_summary(event_survey_id, EventSurveyState::Draft)
        },

        closed_at: None,
        description: Some("Tell us how it went.".to_string()),
        opens_at: None,
        updated_at: None,
    }
}

/// Sample event survey summary in the given state.
pub(crate) fn sample_event_survey_summary(
    event_survey_id: Uuid,
    state: EventSurveyState,
) -> EventSurveySummary {
    EventSurveySummary {
        anonymous: true,
        anonymous_locked: false,
        audience: EventSurveyAudience::Confirmed,
        closed_manually: false,
        eligible_count: 40,
        eligible_respondents_count: 12,
        event_survey_id,
        locked: false,
        questions_count: 1,
        responses_count: 12,
        revision: 3,
        state,
        title: "Session feedback".to_string(),

        closes_at: None,
        effective_opens_at: None,
        open_notification_processed_at: None,
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

/// Sample minimal group used in dashboard selectors and the explore map.
pub(crate) fn sample_group_minimal(group_id: Uuid) -> GroupMinimal {
    GroupMinimal {
        active: true,
        community_name: "test-community".to_string(),
        group_id,
        name: "Test Group".to_string(),
        slug: "test-group".to_string(),

        latitude: Some(37.0),
        longitude: Some(-122.0),
        slug_pretty: None,
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
        region: Some(sample_group_region()),
        slug_pretty: None,
        state: Some("CA".to_string()),
    }
}

/// Sample open inbox conversation started from a public event.
pub(crate) fn sample_inbox_conversation(inbox_conversation_id: Uuid) -> InboxConversation {
    let created_at = Utc.with_ymd_and_hms(2030, 1, 10, 10, 0, 0).unwrap();
    let user = User {
        user_id: Uuid::new_v4(),
        username: "inbox-user".to_string(),

        name: Some("Inbox User".to_string()),
        ..Default::default()
    };

    InboxConversation {
        community_display_name: "Test Community".to_string(),
        community_name: "test".to_string(),
        created_at,
        group_name: "Test Group".to_string(),
        group_slug: "test-group".to_string(),
        inbox_conversation_id,
        last_message_at: created_at,
        messages: vec![InboxMessage {
            body: "When do doors open?".to_string(),
            created_at,
            inbox_message_id: Uuid::new_v4(),
            kind: InboxMessageKind::Initial,

            author: Some(user.clone()),
        }],
        status: InboxConversationStatus::Open,

        event: Some(InboxEvent {
            is_public: true,
            name: "Test Event".to_string(),

            slug: Some("test-event".to_string()),
        }),
        group_slug_pretty: None,
        user: Some(user),
    }
}

/// Sample open inbox conversation summary used by list pages.
pub(crate) fn sample_inbox_conversation_summary(
    inbox_conversation_id: Uuid,
) -> InboxConversationSummary {
    let last_message_at = Utc.with_ymd_and_hms(2030, 1, 10, 10, 0, 0).unwrap();

    InboxConversationSummary {
        community_display_name: "Test Community".to_string(),
        group_name: "Test Group".to_string(),
        inbox_conversation_id,
        last_message_at,
        last_message_excerpt: "When do doors open?".to_string(),
        last_message_kind: InboxMessageKind::Initial,
        status: InboxConversationStatus::Open,

        event: Some(InboxEvent {
            is_public: true,
            name: "Test Event".to_string(),

            slug: None,
        }),
        user: Some(User {
            user_id: Uuid::new_v4(),
            username: "inbox-user".to_string(),

            name: Some("Inbox User".to_string()),
            ..Default::default()
        }),
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

/// Sample optional free-text survey question.
pub(crate) fn sample_survey_question(question_id: Uuid) -> QuestionnaireQuestion {
    QuestionnaireQuestion {
        id: question_id,
        kind: QuestionnaireQuestionKind::FreeText,
        prompt: "What should we improve?".to_string(),
        required: false,

        options: vec![],
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

/// Sample open anonymous survey the user can answer, with one required
/// free-text question.
pub(crate) fn sample_user_event_survey(event_survey_id: Uuid, event_id: Uuid) -> UserEventSurvey {
    UserEventSurvey {
        anonymous: true,
        event: sample_event_summary(event_id, Uuid::new_v4()),
        event_survey_id,
        questions: vec![QuestionnaireQuestion {
            required: true,
            ..sample_survey_question(Uuid::from_u128(0x5d01))
        }],
        revision: 4,
        title: "Session feedback".to_string(),

        closes_at: None,
        description: Some("Tell us how it went.".to_string()),
        response: None,
    }
}

/// Sample open survey of the My Events surveys panel, without a closing date.
pub(crate) fn sample_user_event_survey_item(
    event_survey_id: Uuid,
    answered: bool,
) -> UserEventSurveyItem {
    UserEventSurveyItem {
        answered,
        event_name: "Sample Event".to_string(),
        event_survey_id,
        group_name: "Test Group".to_string(),
        timezone: UTC,
        title: "Session feedback".to_string(),

        closes_at: None,
    }
}

/// Sample user entry returned by dashboard user searches.
pub(crate) fn sample_user_search_result(user_id: Uuid) -> UserSearchResult {
    UserSearchResult {
        user_id,
        username: "test-user".to_string(),

        name: Some("Test User".to_string()),
        photo_url: Some("https://example.test/avatar.png".to_string()),
    }
}
