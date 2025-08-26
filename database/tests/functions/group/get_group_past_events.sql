-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (for testing group past events)
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- group with location data
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'San Francisco', 'CA', 'US', 'United States');

-- event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech Talks', 'tech-talks', :'communityID');

-- events (mix of past, future, published, and unpublished)
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    logo_url,
    venue_city
) values
    -- Past published event (oldest)
    (:'event1ID', 'Past Event 1', 'past-event-1', 'First past event', 'UTC',
     :'eventCategoryID', 'in-person', :'groupID', true,
     '2024-01-01 09:00:00+00', '2024-01-01 11:00:00+00',
     'https://example.com/past-event-1.png', 'San Francisco'),
    -- Past published event (newer)
    (:'event2ID', 'Past Event 2', 'past-event-2', 'Second past event', 'UTC',
     :'eventCategoryID', 'virtual', :'groupID', true,
     '2024-01-10 09:00:00+00', '2024-01-10 11:00:00+00',
     'https://example.com/past-event-2.png', 'Online'),
    -- Past unpublished event (should not be included)
    (:'event3ID', 'Past Event 3', 'past-event-3', 'Unpublished past event', 'UTC',
     :'eventCategoryID', 'hybrid', :'groupID', false,
     '2024-01-05 09:00:00+00', '2024-01-05 11:00:00+00',
     null, 'New York'),
    -- Future event (should not be included)
    (:'event4ID', 'Future Event', 'future-event', 'A future event', 'UTC',
     :'eventCategoryID', 'virtual', :'groupID', true,
     '2026-02-01 09:00:00+00', '2026-02-01 11:00:00+00',
     null, 'Los Angeles');

-- get_group_past_events function returns correct data
select is(
    get_group_past_events('00000000-0000-0000-0000-000000000001'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[
        {
            "event_id": "00000000-0000-0000-0000-000000000042",
            "kind": "virtual",
            "name": "Past Event 2",
            "slug": "past-event-2",
            "logo_url": "https://example.com/past-event-2.png",
            "timezone": "UTC",
            "starts_at": 1704877200,
            "group_city": "San Francisco",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "venue_city": "Online",
            "group_state": "CA",
            "group_country_code": "US",
            "group_country_name": "United States"
        },
        {
            "event_id": "00000000-0000-0000-0000-000000000041",
            "kind": "in-person",
            "name": "Past Event 1",
            "slug": "past-event-1",
            "logo_url": "https://example.com/past-event-1.png",
            "timezone": "UTC",
            "starts_at": 1704099600,
            "group_city": "San Francisco",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "venue_city": "San Francisco",
            "group_state": "CA",
            "group_country_code": "US",
            "group_country_name": "United States"
        }
    ]'::jsonb,
    'get_group_past_events should return published past events ordered by date DESC as JSON'
);

-- get_group_past_events with non-existing group slug
select is(
    get_group_past_events('00000000-0000-0000-0000-000000000001'::uuid, 'non-existing-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[]'::jsonb,
    'get_group_past_events with non-existing group slug should return empty array'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
