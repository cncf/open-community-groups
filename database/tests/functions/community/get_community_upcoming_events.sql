-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'
\set event5ID '00000000-0000-0000-0000-000000000045'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'

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
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name, logo_url)
values (:'group1ID', 'Test Group', 'test-group', :'communityID', :'category1ID', 'New York', 'NY', 'US', 'United States', 'https://example.com/group-logo.png');

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
    canceled,
    logo_url
) values
    -- Past event
    (:'event1ID', 'Past Event', 'past-event', 'A past event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     now() - interval '1 year', now() - interval '1 year' + interval '2 hours', false, null),
    -- Future event 1 (with logo)
    (:'event2ID', 'Future Event 1', 'future-event-1', 'A future event', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     now() + interval '1 month', now() + interval '1 month' + interval '2 hours', false,
     'https://example.com/event-logo.png'),
    -- Future event 2 (unpublished)
    (:'event3ID', 'Future Event 2', 'future-event-2', 'An unpublished event', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', false,
     now() + interval '3 months', now() + interval '3 months' + interval '2 hours', false, null),
    -- Future event 3 (canceled - should be filtered out)
    (:'event4ID', 'Canceled Future Event', 'canceled-future-event', 'A canceled event', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', false,
     now() + interval '2 weeks', now() + interval '2 weeks' + interval '2 hours', true, null),
    -- Future event 4 (no logo - should be filtered out)
    (:'event5ID', 'No Logo Event', 'no-logo-event', 'An event without logo', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     now() + interval '1 month' + interval '1 day', now() + interval '1 month' + interval '1 day' + interval '2 hours',
     false, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include events with group logo (event has no logo but group does)
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should include events with group logo (event has no logo but group does)'
);

-- Should exclude events without any logo (event or group)
update "group" set logo_url = null where group_id = :'group1ID';
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should exclude events without any logo (event or group)'
);
update "group" set logo_url = 'https://example.com/group-logo.png' where group_id = :'group1ID';

-- Should return only published future events with logo
delete from event where event_id = :'event5ID';
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should return only published future events with logo'
);

-- Should return empty array for non-existing community
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-999999999999'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    '[]'::jsonb,
    'Should return empty array for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
