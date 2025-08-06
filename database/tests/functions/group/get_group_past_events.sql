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

-- Seed group
insert into "group" (group_id, name, slug, community_id, group_category_id)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed events (mix of past, future, published, and unpublished)
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
    -- Past published event (oldest)
    (:'event1ID', 'Past Event 1', 'past-event-1', 'First past event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2024-01-01 10:00:00', '2024-01-01 12:00:00'),
    -- Past published event (newer)
    (:'event2ID', 'Past Event 2', 'past-event-2', 'Second past event', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2024-01-10 10:00:00', '2024-01-10 12:00:00'),
    -- Past unpublished event (should not be included)
    (:'event3ID', 'Past Event 3', 'past-event-3', 'Unpublished past event', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', false,
     '2024-01-05 10:00:00', '2024-01-05 12:00:00'),
    -- Future event (should not be included)
    (:'event4ID', 'Future Event', 'future-event', 'A future event', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-01 10:00:00', '2026-02-01 12:00:00');

-- Test get_group_past_events function returns correct data
select is(
    get_group_past_events('00000000-0000-0000-0000-000000000001'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[
        {
            "kind": "virtual",
            "name": "Past Event 2",
            "slug": "past-event-2",
            "logo_url": null,
            "timezone": "UTC",
            "starts_at": 1704877200,
            "group_city": null,
            "group_name": "Test Group",
            "group_slug": "test-group",
            "venue_city": null,
            "group_state": null,
            "group_country_code": null,
            "group_country_name": null
        },
        {
            "kind": "in-person",
            "name": "Past Event 1",
            "slug": "past-event-1",
            "logo_url": null,
            "timezone": "UTC",
            "starts_at": 1704099600,
            "group_city": null,
            "group_name": "Test Group",
            "group_slug": "test-group",
            "venue_city": null,
            "group_state": null,
            "group_country_code": null,
            "group_country_name": null
        }
    ]'::jsonb,
    'get_group_past_events should return published past events ordered by date DESC as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;