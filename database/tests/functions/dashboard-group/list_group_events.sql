-- Tests listing group events for dashboard administration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set community1ID '3a200000-0000-0000-0000-000000000001'
\set event1ID '3a200000-0000-0000-0000-000000000002'
\set event2ID '3a200000-0000-0000-0000-000000000003'
\set event3ID '3a200000-0000-0000-0000-000000000004'
\set event4ID '3a200000-0000-0000-0000-000000000005'
\set event5ID '3a200000-0000-0000-0000-000000000006'
\set event6ID '3a200000-0000-0000-0000-000000000013'
\set eventCategoryID '3a200000-0000-0000-0000-000000000007'
\set group1ID '3a200000-0000-0000-0000-000000000008'
\set group2ID '3a200000-0000-0000-0000-000000000009'
\set group3ID '3a200000-0000-0000-0000-000000000014'
\set groupCategory1ID '3a200000-0000-0000-0000-000000000010'
\set missingGroupID '3a200000-0000-0000-0000-000000000011'
\set user1ID '3a200000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'community1ID', jsonb_build_object(
    'display_name', 'Test Community',
    'logo_url', 'https://example.com/logo.png',
    'name', 'test-community-list-group-events'
));

-- Baseline event categories
select fx_event_category(:'eventCategoryID', :'community1ID');

-- User
select fx_user(:'user1ID', jsonb_build_object(
    'name', 'Creator User',
    'username', 'creator-list-group-events'
));

-- Group Category
select fx_group_category(:'groupCategory1ID', :'community1ID', jsonb_build_object('name', 'Technology'));

-- Group
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'name', 'Test Group',
    'slug', 'test-group',
    'state', 'CA'
));
select fx_group(:'group2ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'name', 'Another Group',
    'slug', 'another-group',
    'state', 'NY'
));
select fx_group(:'group3ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'Madrid',
    'country_code', 'ES',
    'country_name', 'Spain'
));

-- Event
select fx_event(:'event1ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'created_at', '2024-01-01 00:00:00',
    'created_by', :'user1ID',
    'logo_url', 'https://example.com/future-logo.png',
    'name', 'Future Event',
    'slug', 'future-event',
    'starts_at', '2099-12-01 10:00:00+00',
    'timezone', 'America/New_York',
    'venue_city', 'San Francisco'
));
select fx_event(:'event2ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'created_at', '2024-01-02 00:00:00',
    'event_kind_id', 'virtual',
    'name', 'Past Event',
    'slug', 'past-event',
    'starts_at', '2000-01-15 14:00:00+00',
    'timezone', 'America/Los_Angeles'
));
select fx_event(:'event3ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'created_at', '2024-01-03 00:00:00',
    'event_kind_id', 'hybrid',
    'logo_url', 'https://example.com/no-date-logo.png',
    'name', 'Event Without Date',
    'slug', 'event-without-date',
    'timezone', 'Europe/London',
    'venue_city', 'London'
));
select fx_event(:'event4ID', :'group2ID', :'eventCategoryID', jsonb_build_object(
    'created_at', '2024-01-04 00:00:00',
    'name', 'Other Group Event',
    'slug', 'other-group-event',
    'starts_at', '2099-06-01 09:00:00+00',
    'timezone', 'America/Chicago',
    'venue_city', 'Chicago'
));

-- Event (deleted)
select fx_event(:'event5ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'created_at', '2024-01-05 00:00:00',
    'deleted', true,
    'event_kind_id', 'virtual',
    'starts_at', '2025-03-15 10:00:00+00',
    'timezone', 'America/New_York'
));

-- Ongoing event that started in the past but has not ended
select fx_event(:'event6ID', :'group3ID', :'eventCategoryID', jsonb_build_object(
    'description', 'Ongoing event',
    'ends_at', current_timestamp + interval '1 hour',
    'starts_at', current_timestamp - interval '1 hour',
    'timezone', 'Europe/Madrid'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep an ongoing event in the upcoming collection until it ends
select results_eq(
    format($$
        with payload as (
            select list_group_events(
                %L::uuid,
                '{"limit": 50, "past_offset": 0, "upcoming_offset": 0}'::jsonb
            )::jsonb as value
        )
        select
            (value->'past'->>'total')::int,
            value->'upcoming'->'events'->0->>'event_id',
            (value->'upcoming'->>'total')::int
        from payload
    $$, :'group3ID'),
    format($$ values (0, %L::text, 1) $$, :'event6ID'),
    'Should keep an ongoing event in the upcoming collection until it ends'
);

select is(
    list_group_events(
        :'missingGroupID'::uuid,
        '{"limit": 50, "past_offset": 0, "upcoming_offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'past', jsonb_build_object('events', '[]'::jsonb, 'total', 0),
        'upcoming', jsonb_build_object('events', '[]'::jsonb, 'total', 0)
    ),
    'Should return empty arrays for group with no events'
);

select is(
    list_group_events(
        :'group1ID'::uuid,
        '{"limit": 50, "past_offset": 0, "upcoming_offset": 0}'::jsonb
    )::jsonb,
    format(
        '{
        "past": {
            "events": [
                {
                    "attendee_count": 0,
                    "canceled": false,
                    "community_display_name": "Test Community",
                    "community_name": "test-community-list-group-events",
                    "delete_eligibility": "allowed",
                    "event_id": "%s",
                    "group_category_name": "Technology",
                    "group_name": "Test Group",
                    "group_slug": "test-group",
                    "has_registration_questions": false,
                    "has_related_events": false,
                    "kind": "virtual",
                    "name": "Past Event",
                    "published": false,
                    "slug": "past-event",
                    "test_event": false,
                    "timezone": "America/Los_Angeles",

                    "attendee_approval_required": false,
                    "logo_url": "https://example.com/logo.png",
                    "starts_at": 947944800,
                    "waitlist_count": 0,
                    "waitlist_enabled": false
                }
            ],
            "total": 1
        },
        "upcoming": {
            "events": [
                {
                    "attendee_count": 0,
                    "canceled": false,
                    "community_display_name": "Test Community",
                    "community_name": "test-community-list-group-events",
                    "delete_eligibility": "allowed",
                    "event_id": "%s",
                    "group_category_name": "Technology",
                    "group_name": "Test Group",
                    "group_slug": "test-group",
                    "has_registration_questions": false,
                    "has_related_events": false,
                    "kind": "in-person",
                    "name": "Future Event",
                    "published": false,
                    "slug": "future-event",
                    "test_event": false,
                    "timezone": "America/New_York",

                    "attendee_approval_required": false,
                    "logo_url": "https://example.com/future-logo.png",
                    "starts_at": 4099802400,
                    "venue_city": "San Francisco",
                    "waitlist_count": 0,
                    "waitlist_enabled": false,

                    "created_by_display_name": "Creator User",
                    "created_by_username": "creator-list-group-events"
                },
                {
                    "attendee_count": 0,
                    "canceled": false,
                    "community_display_name": "Test Community",
                    "community_name": "test-community-list-group-events",
                    "delete_eligibility": "allowed",
                    "event_id": "%s",
                    "group_category_name": "Technology",
                    "group_name": "Test Group",
                    "group_slug": "test-group",
                    "has_registration_questions": false,
                    "has_related_events": false,
                    "kind": "hybrid",
                    "name": "Event Without Date",
                    "published": false,
                    "slug": "event-without-date",
                    "test_event": false,
                    "timezone": "Europe/London",

                    "attendee_approval_required": false,
                    "logo_url": "https://example.com/no-date-logo.png",
                    "venue_city": "London",
                    "waitlist_count": 0,
                    "waitlist_enabled": false
                }
            ],
            "total": 2
        }
    }',
        :'event2ID', :'event1ID', :'event3ID'
    )::jsonb,
    'Should group events by timeframe with ordering'
);

-- Should return correct grouped JSON for specified group
select is(
    list_group_events(
        :'group2ID'::uuid,
        '{"limit": 50, "past_offset": 0, "upcoming_offset": 0}'::jsonb
    )::jsonb,
    format(
        '{
        "past": {
            "events": [],
            "total": 0
        },
        "upcoming": {
            "events": [
                {
                    "attendee_count": 0,
                    "canceled": false,
                    "community_display_name": "Test Community",
                    "community_name": "test-community-list-group-events",
                    "delete_eligibility": "allowed",
                    "event_id": "%s",
                    "group_category_name": "Technology",
                    "group_name": "Another Group",
                    "group_slug": "another-group",
                    "has_registration_questions": false,
                    "has_related_events": false,
                    "kind": "in-person",
                    "name": "Other Group Event",
                    "published": false,
                    "slug": "other-group-event",
                    "test_event": false,
                    "timezone": "America/Chicago",

                    "attendee_approval_required": false,
                    "logo_url": "https://example.com/logo.png",
                    "starts_at": 4083987600,
                    "venue_city": "Chicago",
                    "waitlist_count": 0,
                    "waitlist_enabled": false
                }
            ],
            "total": 1
        }
    }',
        :'event4ID'
    )::jsonb,
    'Should return correct grouped JSON for specified group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
