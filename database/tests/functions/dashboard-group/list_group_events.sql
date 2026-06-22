-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set alliance1ID '3a200000-0000-0000-0000-000000000001'
\set event1ID '3a200000-0000-0000-0000-000000000002'
\set event2ID '3a200000-0000-0000-0000-000000000003'
\set event3ID '3a200000-0000-0000-0000-000000000004'
\set event4ID '3a200000-0000-0000-0000-000000000005'
\set event5ID '3a200000-0000-0000-0000-000000000006'
\set eventCategoryID '3a200000-0000-0000-0000-000000000007'
\set group1ID '3a200000-0000-0000-0000-000000000008'
\set group2ID '3a200000-0000-0000-0000-000000000009'
\set groupCategory1ID '3a200000-0000-0000-0000-000000000010'
\set missingGroupID '3a200000-0000-0000-0000-000000000011'
\set user1ID '3a200000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'alliance1ID',
    'test-alliance',
    'Test Alliance',
    'A test alliance for testing purposes',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'Conference', :'alliance1ID');

-- User
insert into "user" (user_id, email, username, auth_hash, name)
values (:'user1ID', 'creator@example.com', 'creator', 'hash', 'Creator User');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategory1ID', 'Technology', :'alliance1ID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id,
    city,
    state,
    country_code,
    country_name
) values 
    (
        :'group1ID',
        :'alliance1ID',
        'Test Group',
        'test-group',
        'A test group',
        :'groupCategory1ID',
        'San Francisco',
        'CA',
        'US',
        'United States'
    ),
    (
        :'group2ID',
        :'alliance1ID',
        'Another Group',
        'another-group',
        'Another test group',
        :'groupCategory1ID',
        'New York',
        'NY',
        'US',
        'United States'
    );

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    event_category_id,
    event_kind_id,
    timezone,
    starts_at,
    created_at,
    logo_url,
    venue_city,

    created_by
) values 
    (
        :'event1ID',
        :'group1ID',
        'Future Event',
        'future-event',
        'An event in the future',
        :'eventCategoryID',
        'in-person',
        'America/New_York',
        '2099-12-01 10:00:00+00',
        '2024-01-01 00:00:00',
        'https://example.com/future-logo.png',
        'San Francisco',

        :'user1ID'
    ),
    (
        :'event2ID',
        :'group1ID',
        'Past Event',
        'past-event',
        'An event in the past',
        :'eventCategoryID',
        'virtual',
        'America/Los_Angeles',
        '2000-01-15 14:00:00+00',
        '2024-01-02 00:00:00',
        null,
        null,

        null
    ),
    (
        :'event3ID',
        :'group1ID',
        'Event Without Date',
        'event-without-date',
        'An event without a start date',
        :'eventCategoryID',
        'hybrid',
        'Europe/London',
        null,
        '2024-01-03 00:00:00',
        'https://example.com/no-date-logo.png',
        'London',

        null
    ),
    (
        :'event4ID',
        :'group2ID',
        'Other Group Event',
        'other-group-event',
        'Event in different group',
        :'eventCategoryID',
        'in-person',
        'America/Chicago',
        '2099-06-01 09:00:00+00',
        '2024-01-04 00:00:00',
        null,
        'Chicago',

        null
    );

-- Event (deleted)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    event_category_id,
    event_kind_id,
    timezone,
    starts_at,
    created_at,
    deleted
) values (
    :'event5ID',
    :'group1ID',
    'Deleted Event',
    'deleted-event',
    'An event that has been deleted',
    :'eventCategoryID',
    'virtual',
    'America/New_York',
    '2025-03-15 10:00:00+00',
    '2024-01-05 00:00:00',
    true
);

-- ============================================================================
-- TESTS
-- ============================================================================

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
                    "canceled": false,
                    "alliance_display_name": "Test Alliance",
                    "alliance_name": "test-alliance",
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
                    "canceled": false,
                    "alliance_display_name": "Test Alliance",
                    "alliance_name": "test-alliance",
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
                    "created_by_username": "creator"
                },
                {
                    "canceled": false,
                    "alliance_display_name": "Test Alliance",
                    "alliance_name": "test-alliance",
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
                    "canceled": false,
                    "alliance_display_name": "Test Alliance",
                    "alliance_name": "test-alliance",
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
