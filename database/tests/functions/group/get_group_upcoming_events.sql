-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'

-- Seed community
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
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed group with location data
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID', 'Los Angeles', 'CA', 'US', 'United States');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed events (mix of past, future, published, and unpublished)
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
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
    -- Past event (should not be included)
    (:'event1ID', 'Past Event', 'past-event', 'A past event', 'A past event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2024-01-01 10:00:00+00', '2024-01-01 12:00:00+00',
     null, 'San Francisco'),
    -- Future published event (closest)
    (:'event2ID', 'Future Event 1', 'future-event-1', 'First future event', 'First future event', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-01 09:00:00+00', '2026-02-01 11:00:00+00',
     'https://example.com/future-event-1.png', 'Online'),
    -- Future published event (later)
    (:'event3ID', 'Future Event 2', 'future-event-2', 'Second future event', 'Second future event', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', true,
     '2026-02-10 09:00:00+00', '2026-02-10 11:00:00+00',
     'https://example.com/future-event-2.png', 'Los Angeles'),
    -- Future unpublished event (should not be included)
    (:'event4ID', 'Future Event 3', 'future-event-3', 'Unpublished future event', 'Unpublished future event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', false,
     '2026-02-20 09:00:00+00', '2026-02-20 11:00:00+00',
     null, 'New York');

-- Test: get_group_upcoming_events function returns correct data
select is(
    get_group_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[
        {
            "canceled": false,
            "event_id": "00000000-0000-0000-0000-000000000042",
            "group_category_name": "Technology",
            "kind": "virtual",
            "name": "Future Event 1",
            "slug": "future-event-1",
            "logo_url": "https://example.com/future-event-1.png",
            "timezone": "UTC",
            "starts_at": 1769936400,
            "ends_at": 1769943600,
            "description_short": "First future event",
            "group_city": "Los Angeles",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "venue_city": "Online",
            "group_state": "CA",
            "group_country_code": "US",
            "group_country_name": "United States"
        },
        {
            "canceled": false,
            "event_id": "00000000-0000-0000-0000-000000000043",
            "group_category_name": "Technology",
            "kind": "hybrid",
            "name": "Future Event 2",
            "slug": "future-event-2",
            "logo_url": "https://example.com/future-event-2.png",
            "timezone": "UTC",
            "starts_at": 1770714000,
            "ends_at": 1770721200,
            "description_short": "Second future event",
            "group_city": "Los Angeles",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "venue_city": "Los Angeles",
            "group_state": "CA",
            "group_country_code": "US",
            "group_country_name": "United States"
        }
    ]'::jsonb,
    'get_group_upcoming_events should return published future events ordered by date ASC as JSON'
);

-- Test: get_group_upcoming_events with non-existing group slug
select is(
    get_group_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, 'non-existing-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[]'::jsonb,
    'get_group_upcoming_events with non-existing group slug should return empty array'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;