-- Tests checking whether events linked from the inbox are publicly available.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1b150000-0000-0000-0000-000000000001'
\set deletedEventID '1b150000-0000-0000-0000-000000000002'
\set deletedGroupEventID '1b150000-0000-0000-0000-000000000003'
\set deletedGroupID '1b150000-0000-0000-0000-000000000004'
\set eventCategoryID '1b150000-0000-0000-0000-000000000005'
\set eventID '1b150000-0000-0000-0000-000000000006'
\set groupCategoryID '1b150000-0000-0000-0000-000000000007'
\set groupID '1b150000-0000-0000-0000-000000000008'
\set inactiveGroupEventID '1b150000-0000-0000-0000-000000000009'
\set inactiveGroupID '1b150000-0000-0000-0000-000000000010'
\set unpublishedEventID '1b150000-0000-0000-0000-000000000011'

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
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Deleted group
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Published event of an active group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Deleted event
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- Published event of a deleted group
select fx_event(:'deletedGroupEventID', :'deletedGroupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published event of an inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Unpublished event
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept published events of active groups
select is(
    (select is_inbox_event_public(e, g) from event e join "group" g using (group_id) where e.event_id = :'eventID'),
    true,
    'Should accept published events of active groups'
);

-- Should reject deleted events
select is(
    (select is_inbox_event_public(e, g) from event e join "group" g using (group_id) where e.event_id = :'deletedEventID'),
    false,
    'Should reject deleted events'
);

-- Should reject events of deleted groups
select is(
    (select is_inbox_event_public(e, g) from event e join "group" g using (group_id) where e.event_id = :'deletedGroupEventID'),
    false,
    'Should reject events of deleted groups'
);

-- Should reject events of inactive groups
select is(
    (select is_inbox_event_public(e, g) from event e join "group" g using (group_id) where e.event_id = :'inactiveGroupEventID'),
    false,
    'Should reject events of inactive groups'
);

-- Should reject unpublished events
select is(
    (select is_inbox_event_public(e, g) from event e join "group" g using (group_id) where e.event_id = :'unpublishedEventID'),
    false,
    'Should reject unpublished events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
