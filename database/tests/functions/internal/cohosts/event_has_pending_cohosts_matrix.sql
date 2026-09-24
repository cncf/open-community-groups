-- Tests event_has_pending_cohosts active, inactive, and empty cases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activePendingGroupID 'e5120000-0000-0000-0000-000000000001'
\set communityID 'e5120000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5120000-0000-0000-0000-000000000003'
\set eventNoPendingID 'e5120000-0000-0000-0000-000000000004'
\set eventPendingActiveID 'e5120000-0000-0000-0000-000000000005'
\set eventPendingInactiveID 'e5120000-0000-0000-0000-000000000006'
\set groupCategoryID 'e5120000-0000-0000-0000-000000000007'
\set groupID 'e5120000-0000-0000-0000-000000000008'
\set inactivePendingGroupID 'e5120000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'activePendingGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'inactivePendingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));
select fx_event(:'eventNoPendingID', :'groupID', :'eventCategoryID');
select fx_event(:'eventPendingActiveID', :'groupID', :'eventCategoryID');
select fx_event(:'eventPendingInactiveID', :'groupID', :'eventCategoryID');

-- Pending rows for active and inactive groups
insert into event_cohost (event_id, group_id) values
    (:'eventPendingActiveID', :'activePendingGroupID'),
    (:'eventPendingInactiveID', :'inactivePendingGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false when no pending co-host exists
select is(event_has_pending_cohosts(:'eventNoPendingID'::uuid), false, 'Should return false when no pending co-host exists');

-- Should return true when an active group is pending
select is(event_has_pending_cohosts(:'eventPendingActiveID'::uuid), true, 'Should return true when an active group is pending');

-- Should return true when an inactive group is pending
select is(event_has_pending_cohosts(:'eventPendingInactiveID'::uuid), true, 'Should return true when an inactive group is pending');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
