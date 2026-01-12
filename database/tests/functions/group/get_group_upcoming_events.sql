-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_url)
values (:'community1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID', 'Los Angeles', 'CA', 'US', 'United States');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Event
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published future events ordered by date ASC as JSON
select is(
    get_group_upcoming_events(:'community1ID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should return published future events ordered by date ASC as JSON'
);

-- Should return empty array with non-existing group slug
select is(
    get_group_upcoming_events(:'community1ID'::uuid, 'non-existing-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    '[]'::jsonb,
    'Should return empty array with non-existing group slug'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
