-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'
\set eventCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'San Francisco', 'CA', 'US', 'United States');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech Talks', 'tech-talks', :'communityID');

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
    logo_url,
    venue_city
) values
    -- Past published event (oldest)
    (:'event1ID', 'Past Event 1', 'past-event-1', 'First past event', 'UTC',
     :'eventCategoryID', 'in-person', :'groupID', true,
     now() - interval '1 year', now() - interval '1 year' + interval '2 hours',
     'https://example.com/past-event-1.png', 'San Francisco'),
    -- Past published event (newer)
    (:'event2ID', 'Past Event 2', 'past-event-2', 'Second past event', 'UTC',
     :'eventCategoryID', 'virtual', :'groupID', true,
     now() - interval '11 months', now() - interval '11 months' + interval '2 hours',
     'https://example.com/past-event-2.png', 'Online'),
    -- Past unpublished event (should not be included)
    (:'event3ID', 'Past Event 3', 'past-event-3', 'Unpublished past event', 'UTC',
     :'eventCategoryID', 'hybrid', :'groupID', false,
     now() - interval '1 year' + interval '5 days', now() - interval '1 year' + interval '5 days' + interval '2 hours',
     null, 'New York'),
    -- Future event (should not be included)
    (:'event4ID', 'Future Event', 'future-event', 'A future event', 'UTC',
     :'eventCategoryID', 'virtual', :'groupID', true,
     now() + interval '1 year', now() + interval '1 year' + interval '2 hours',
     null, 'Los Angeles');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published past events ordered by date DESC as JSON
select is(
    get_group_past_events('00000000-0000-0000-0000-000000000001'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should return published past events ordered by date DESC as JSON'
);


-- Finish tests and rollback transaction
select * from finish();
rollback;
