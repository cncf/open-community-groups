-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name)
values (:'group1ID', 'Test Group', 'test-group', :'communityID', :'category1ID', 'New York', 'NY', 'US', 'United States');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'communityID');

-- Event
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
    canceled
) values
    -- Past event
    (:'event1ID', 'Past Event', 'past-event', 'A past event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2024-01-01 10:00:00+00', '2024-01-01 12:00:00+00', false),
    -- Future event 1
    (:'event2ID', 'Future Event 1', 'future-event-1', 'A future event', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-01 09:00:00+00', '2026-02-01 11:00:00+00', false),
    -- Future event 2 (unpublished)
    (:'event3ID', 'Future Event 2', 'future-event-2', 'An unpublished event', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', false,
     '2026-03-01 09:00:00+00', '2026-03-01 11:00:00+00', false),
    -- Future event 3 (canceled - should be filtered out)
    (:'event4ID', 'Canceled Future Event', 'canceled-future-event', 'A canceled event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', false,
     '2026-01-15 14:00:00+00', '2026-01-15 16:00:00+00', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- get_community_upcoming_events function returns correct data
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'get_community_upcoming_events should return only published future events as JSON'
);

-- get_community_upcoming_events with non-existing community
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-999999999999'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    '[]'::jsonb,
    'get_community_upcoming_events with non-existing community should return empty array'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
