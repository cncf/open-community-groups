-- Tests checking whether events appear in public listings and counts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '5ea40000-0000-0000-0000-000000000001'
\set communityID '5ea40000-0000-0000-0000-000000000002'
\set eventCategoryID '5ea40000-0000-0000-0000-000000000003'
\set eventID '5ea40000-0000-0000-0000-000000000004'
\set groupCategoryID '5ea40000-0000-0000-0000-000000000005'
\set groupID '5ea40000-0000-0000-0000-000000000006'
\set inactiveGroupEventID '5ea40000-0000-0000-0000-000000000007'
\set inactiveGroupID '5ea40000-0000-0000-0000-000000000008'
\set testEventID '5ea40000-0000-0000-0000-000000000009'
\set unpublishedEventID '5ea40000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the events
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Published event of an active group that was canceled
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'test_event', false
));

-- Published, not canceled, non-test event of an active group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'published', true,
    'test_event', false
));

-- Published, not canceled, non-test event of an inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'published', true,
    'test_event', false
));

-- Published test event of an active group
select fx_event(:'testEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'published', true,
    'test_event', true
));

-- Unpublished, not canceled, non-test event of an active group
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'published', false,
    'test_event', false
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept published, not canceled, non-test events of active groups
select is(
    (select is_event_listed(e, g) from event e join "group" g using (group_id) where e.event_id = :'eventID'),
    true,
    'Should accept published, not canceled, non-test events of active groups'
);

-- Should be parallel safe so parallel queries can call it
select is(
    (select proparallel from pg_proc where proname = 'is_event_listed'),
    's'::"char",
    'Should be parallel safe so parallel queries can call it'
);

-- Should reject canceled events
select is(
    (select is_event_listed(e, g) from event e join "group" g using (group_id) where e.event_id = :'canceledEventID'),
    false,
    'Should reject canceled events'
);

-- Should reject events of inactive groups
select is(
    (select is_event_listed(e, g) from event e join "group" g using (group_id) where e.event_id = :'inactiveGroupEventID'),
    false,
    'Should reject events of inactive groups'
);

-- Should reject test events
select is(
    (select is_event_listed(e, g) from event e join "group" g using (group_id) where e.event_id = :'testEventID'),
    false,
    'Should reject test events'
);

-- Should reject unpublished events
select is(
    (select is_event_listed(e, g) from event e join "group" g using (group_id) where e.event_id = :'unpublishedEventID'),
    false,
    'Should reject unpublished events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
