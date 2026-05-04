-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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
\set event6ID '00000000-0000-0000-0000-000000000046'
\set event7ID '00000000-0000-0000-0000-000000000047'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'

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

insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url)
values (:'group2ID', 'Virtual Group', 'virtual-group', :'communityID', :'category1ID', 'https://example.com/virtual-group-logo.png');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategory1ID', 'Tech Talks', :'communityID');

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
    -- Future event 4 (uses group logo fallback)
    (:'event5ID', 'No Logo Event', 'no-logo-event', 'An event without logo', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     now() + interval '1 month' + interval '1 day', now() + interval '1 month' + interval '1 day' + interval '2 hours',
     false, null),
    -- Future event 5 (virtual event for a group without location data)
    (:'event7ID', 'Locationless Virtual Event', 'locationless-virtual-event',
     'A virtual event for a group without location data', 'UTC',
     :'eventCategory1ID', 'virtual', :'group2ID', true,
     now() + interval '3 months', now() + interval '3 months' + interval '2 hours',
     false, 'https://example.com/locationless-virtual-event-logo.png');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published future events
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event7ID'::uuid)::jsonb
    ),
    'Should return published future events'
);

-- Should return only published future events matching event kind filter
delete from event where event_id = :'event5ID';
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-000000000001'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event7ID'::uuid)::jsonb
    ),
    'Should return only published future events'
);

-- Should return empty array for non-existing community
select is(
    get_community_upcoming_events('00000000-0000-0000-0000-999999999999'::uuid, array['in-person', 'virtual', 'hybrid'])::jsonb,
    '[]'::jsonb,
    'Should return empty array for non-existing community'
);

-- Add a tied future event to verify deterministic ordering
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
) values (
    :'event6ID',
    'Future Event 5',
    'future-event-5',
    'A future event with a tied start time',
    'UTC',
    :'eventCategory1ID',
    'virtual',
    :'group1ID',
    true,
    now() + interval '1 month',
    now() + interval '1 month' + interval '4 hours',
    false,
    'https://example.com/event-5-logo.png'
);

-- Should order tied future events by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(
            get_community_upcoming_events(:'communityID'::uuid, array['virtual'])::jsonb
        ) event_item
    ),
    jsonb_build_array(:'event2ID', :'event6ID', :'event7ID'),
    'Should order tied future events by event ID'
);

-- Should include virtual events for groups without location data
select ok(
    exists (
        select 1
        from jsonb_array_elements(
            get_community_upcoming_events(:'communityID'::uuid, array['virtual'])::jsonb
        ) event_item
        where event_item->>'event_id' = :'event7ID'
    ),
    'Should include virtual events for groups without location data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
