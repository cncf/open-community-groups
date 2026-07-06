-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a020000-0000-0000-0000-000000000001'
\set deletedChildEventID '6a020000-0000-0000-0000-00000000000f'
\set deletedChildGroupID '6a020000-0000-0000-0000-00000000000c'
\set event1ID '6a020000-0000-0000-0000-000000000002'
\set event2ID '6a020000-0000-0000-0000-000000000003'
\set event3ID '6a020000-0000-0000-0000-000000000004'
\set event4ID '6a020000-0000-0000-0000-000000000005'
\set event5ID '6a020000-0000-0000-0000-000000000006'
\set childEventID '6a020000-0000-0000-0000-00000000000d'
\set childGroupID '6a020000-0000-0000-0000-00000000000a'
\set eventCategoryID '6a020000-0000-0000-0000-000000000007'
\set groupCategoryID '6a020000-0000-0000-0000-000000000008'
\set groupID '6a020000-0000-0000-0000-000000000009'
\set inactiveChildEventID '6a020000-0000-0000-0000-00000000000e'
\set inactiveChildGroupID '6a020000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A test community',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    city,
    country_code,
    country_name,
    state
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'San Francisco',
    'US',
    'United States',
    'CA'
);

-- Child groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted,

    parent_group_id
) values
    (:'childGroupID', :'communityID', :'groupCategoryID', 'Active Child Group', 'active-child-group', true, false, :'groupID'),
    (:'inactiveChildGroupID', :'communityID', :'groupCategoryID', 'Inactive Child Group', 'inactive-child-group', false, false, :'groupID'),
    (:'deletedChildGroupID', :'communityID', :'groupCategoryID', 'Deleted Child Group', 'deleted-child-group', false, true, :'groupID');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Tech Talks');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    test_event,
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
    (
        :'event1ID',
        'Past Event 1',
        'past-event-1',
        'First past event',
        false,
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        now() - interval '1 year',
        now() - interval '1 year' + interval '2 hours',
        'https://example.com/past-event-1.png',
        'San Francisco'
    ),
    -- Past published event (newer)
    (
        :'event2ID',
        'Past Event 2',
        'past-event-2',
        'Second past event',
        true,
        'UTC',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        true,
        now() - interval '11 months',
        now() - interval '11 months' + interval '2 hours',
        'https://example.com/past-event-2.png',
        'Online'
    ),
    -- Past unpublished event (should not be included)
    (
        :'event3ID',
        'Past Event 3',
        'past-event-3',
        'Unpublished past event',
        false,
        'UTC',
        :'eventCategoryID',
        'hybrid',
        :'groupID',
        false,
        now() - interval '1 year' + interval '5 days',
        now() - interval '1 year' + interval '5 days' + interval '2 hours',
        null,
        'New York'
    ),
    -- Future event (should not be included)
    (
        :'event4ID',
        'Future Event',
        'future-event',
        'A future event',
        false,
        'UTC',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        true,
        now() + interval '1 year',
        now() + interval '1 year' + interval '2 hours',
        null,
        'Los Angeles'
    ),
    -- Past published event (most recent, should be listed first)
    (
        :'event5ID',
        'Past Event 5',
        'past-event-5',
        'Most recent past event',
        false,
        'UTC',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        true,
        now() - interval '6 months',
        now() - interval '6 months' + interval '2 hours',
        'https://example.com/past-event-5.png',
        'Online'
    );

-- Child group events
insert into event (
    event_id,
    name,
    slug,
    description,
    test_event,
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
    (
        :'childEventID',
        'Active Child Past Event',
        'active-child-past-event',
        'Active child past event',
        false,
        'UTC',
        :'eventCategoryID',
        'hybrid',
        :'childGroupID',
        true,
        now() - interval '3 months',
        now() - interval '3 months' + interval '2 hours',
        null,
        'San Francisco'
    ),
    (
        :'inactiveChildEventID',
        'Inactive Child Past Event',
        'inactive-child-past-event',
        'Inactive child past event',
        false,
        'UTC',
        :'eventCategoryID',
        'hybrid',
        :'inactiveChildGroupID',
        true,
        now() - interval '2 months',
        now() - interval '2 months' + interval '2 hours',
        null,
        'San Francisco'
    ),
    (
        :'deletedChildEventID',
        'Deleted Child Past Event',
        'deleted-child-past-event',
        'Deleted child past event',
        false,
        'UTC',
        :'eventCategoryID',
        'hybrid',
        :'deletedChildGroupID',
        true,
        now() - interval '4 months',
        now() - interval '4 months' + interval '2 hours',
        null,
        'San Francisco'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test past events ordered by date DESC as JSON
select is(
    get_group_past_events(:'communityID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'childGroupID'::uuid, :'childEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should return published non-test past events from the group and active children ordered by date DESC as JSON'
);

-- Should resolve past events by pretty slug
update "group" set slug_pretty = 'test-group-pretty' where group_id = :'groupID';
select is(
    get_group_past_events(:'communityID'::uuid, 'test-group-pretty', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'childGroupID'::uuid, :'childEventID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should resolve past events by pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
