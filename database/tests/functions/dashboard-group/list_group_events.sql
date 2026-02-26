-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '00000000-0000-0000-0000-000000000011'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000021'
\set event2ID '00000000-0000-0000-0000-000000000022'
\set event3ID '00000000-0000-0000-0000-000000000023'
\set event4ID '00000000-0000-0000-0000-000000000024'
\set event5ID '00000000-0000-0000-0000-000000000025'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set group2ID '00000000-0000-0000-0000-000000000003'
\set groupCategory1ID '00000000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'category1ID', 'Conference', :'community1ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategory1ID', 'Technology', :'community1ID');

-- Group
insert into "group" (
    group_id,
    community_id,
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
        :'community1ID',
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
        :'community1ID',
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
    venue_city
) values 
    (
        :'event1ID',
        :'group1ID',
        'Future Event',
        'future-event',
        'An event in the future',
        :'category1ID',
        'in-person',
        'America/New_York',
        '2099-12-01 10:00:00+00',
        '2024-01-01 00:00:00',
        'https://example.com/future-logo.png',
        'San Francisco'
    ),
    (
        :'event2ID',
        :'group1ID',
        'Past Event',
        'past-event',
        'An event in the past',
        :'category1ID',
        'virtual',
        'America/Los_Angeles',
        '2000-01-15 14:00:00+00',
        '2024-01-02 00:00:00',
        null,
        null
    ),
    (
        :'event3ID',
        :'group1ID',
        'Event Without Date',
        'event-without-date',
        'An event without a start date',
        :'category1ID',
        'hybrid',
        'Europe/London',
        null,
        '2024-01-03 00:00:00',
        'https://example.com/no-date-logo.png',
        'London'
    ),
    (
        :'event4ID',
        :'group2ID',
        'Other Group Event',
        'other-group-event',
        'Event in different group',
        :'category1ID',
        'in-person',
        'America/Chicago',
        '2099-06-01 09:00:00+00',
        '2024-01-04 00:00:00',
        null,
        'Chicago'
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
    :'category1ID',
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
        '00000000-0000-0000-0000-000000000099'::uuid,
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
    jsonb_build_object(
        'past', jsonb_build_object(
            'events', jsonb_build_array(
                get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
            ),
            'total', 1
        ),
        'upcoming', jsonb_build_object(
            'events', jsonb_build_array(
                get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
                get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
            ),
            'total', 2
        )
    ),
    'Should group events by timeframe with ordering'
);

-- Should return correct grouped JSON for specified group
select is(
    list_group_events(
        :'group2ID'::uuid,
        '{"limit": 50, "past_offset": 0, "upcoming_offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'past', jsonb_build_object('events', '[]'::jsonb, 'total', 0),
        'upcoming', jsonb_build_object(
            'events', jsonb_build_array(
                get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event4ID'::uuid)::jsonb
            ),
            'total', 1
        )
    ),
    'Should return correct grouped JSON for specified group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
