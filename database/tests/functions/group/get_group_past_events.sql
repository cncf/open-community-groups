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

-- Baseline community and categories for group event lookup
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Parent group resolved by slug
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'slug', 'test-group',
    'state', 'CA'
));

-- Child groups used by inherited event lookup
select fx_group(:'childGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'groupID'));
select fx_group(:'inactiveChildGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'parent_group_id', :'groupID'
));
select fx_group(:'deletedChildGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'parent_group_id', :'groupID'
));

-- Events covering past filters and ordering
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '2 hours',
    'published', true,
    'starts_at', now() - interval '1 year'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '11 months' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() - interval '11 months',
    'test_event', true
));
select fx_event(:'event3ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 year' + interval '5 days' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'starts_at', now() - interval '1 year' + interval '5 days'
));
select fx_event(:'event4ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 year' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 year'
));
select fx_event(:'event5ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '6 months' + interval '2 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() - interval '6 months'
));

-- Child group events covering active and inactive children
select fx_event(:'childEventID', :'childGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '3 months' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() - interval '3 months'
));
select fx_event(:'inactiveChildEventID', :'inactiveChildGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '2 months' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() - interval '2 months'
));
select fx_event(:'deletedChildEventID', :'deletedChildGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '4 months' + interval '2 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() - interval '4 months'
));

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
