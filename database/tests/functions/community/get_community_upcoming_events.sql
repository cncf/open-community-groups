-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'

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

-- Seed group with city
insert into "group" (group_id, name, slug, community_id, group_category_id, city)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID', 'New York');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed events (one past, two future, one unpublished)
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
    ends_at
) values
    -- Past event
    (:'event1ID', 'Past Event', 'past-event', 'A past event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2024-01-01 10:00:00+00', '2024-01-01 12:00:00+00'),
    -- Future event 1
    (:'event2ID', 'Future Event 1', 'future-event-1', 'A future event', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-01 09:00:00+00', '2026-02-01 11:00:00+00'),
    -- Future event 2 (unpublished)
    (:'event3ID', 'Future Event 2', 'future-event-2', 'An unpublished event', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', false,
     '2026-03-01 09:00:00+00', '2026-03-01 11:00:00+00');

-- Test get_community_upcoming_events function returns correct data
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    '[
        {
            "group_city": "New York",
            "group_country_code": null,
            "group_country_name": null,
            "group_name": "Test Group",
            "group_slug": "test-group",
            "group_state": null,
            "kind": "virtual",
            "logo_url": null,
            "name": "Future Event 1",
            "slug": "future-event-1",
            "starts_at": 1769936400,
            "timezone": "UTC",
            "venue_city": null
        }
    ]'::jsonb,
    'get_community_upcoming_events should return only published future events as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;