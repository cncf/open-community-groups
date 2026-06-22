-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '6a020000-0000-0000-0000-000000000001'
\set event1ID '6a020000-0000-0000-0000-000000000002'
\set event2ID '6a020000-0000-0000-0000-000000000003'
\set event3ID '6a020000-0000-0000-0000-000000000004'
\set event4ID '6a020000-0000-0000-0000-000000000005'
\set event5ID '6a020000-0000-0000-0000-000000000006'
\set eventCategoryID '6a020000-0000-0000-0000-000000000007'
\set groupCategoryID '6a020000-0000-0000-0000-000000000008'
\set groupID '6a020000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A test alliance',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    city,
    country_code,
    country_name,
    state
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'San Francisco',
    'US',
    'United States',
    'CA'
);

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Tech Talks');

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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return published non-test past events ordered by date DESC as JSON
select is(
    get_group_past_events(:'allianceID'::uuid, 'test-group', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should return published non-test past events ordered by date DESC as JSON'
);

-- Should resolve past events by pretty slug
update "group" set slug_pretty = 'test-group-pretty' where group_id = :'groupID';
select is(
    get_group_past_events(:'allianceID'::uuid, 'test-group-pretty', array['in-person', 'virtual', 'hybrid'], 10)::jsonb,
    jsonb_build_array(
        get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should resolve past events by pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
