-- Tests detecting pending event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e5020000-0000-0000-0000-000000000001'
\set eventCategoryID 'e5020000-0000-0000-0000-000000000002'
\set eventNoCohostsID 'e5020000-0000-0000-0000-000000000003'
\set eventNonPendingCohostsID 'e5020000-0000-0000-0000-000000000004'
\set eventPendingActiveID 'e5020000-0000-0000-0000-000000000005'
\set eventPendingInactiveID 'e5020000-0000-0000-0000-000000000006'
\set groupApprovedID 'e5020000-0000-0000-0000-000000000007'
\set groupCanceledID 'e5020000-0000-0000-0000-000000000008'
\set groupCategoryID 'e5020000-0000-0000-0000-000000000009'
\set groupEventCanceledID 'e5020000-0000-0000-0000-00000000000a'
\set groupEventDeletedID 'e5020000-0000-0000-0000-00000000000b'
\set groupID 'e5020000-0000-0000-0000-00000000000c'
\set groupPendingActiveID 'e5020000-0000-0000-0000-00000000000d'
\set groupPendingInactiveID 'e5020000-0000-0000-0000-00000000000e'
\set groupRejectedID 'e5020000-0000-0000-0000-00000000000f'
\set groupRemovedID 'e5020000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Host group that owns every event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Co-host groups, one per invitation status
select fx_group(:'groupApprovedID', :'communityID', :'groupCategoryID');
select fx_group(:'groupCanceledID', :'communityID', :'groupCategoryID');
select fx_group(:'groupEventCanceledID', :'communityID', :'groupCategoryID');
select fx_group(:'groupEventDeletedID', :'communityID', :'groupCategoryID');
select fx_group(:'groupPendingActiveID', :'communityID', :'groupCategoryID');
select fx_group(:'groupPendingInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));
select fx_group(:'groupRejectedID', :'communityID', :'groupCategoryID');
select fx_group(:'groupRemovedID', :'communityID', :'groupCategoryID');

-- Events, one per scenario
select fx_event(:'eventNoCohostsID', :'groupID', :'eventCategoryID');
select fx_event(:'eventNonPendingCohostsID', :'groupID', :'eventCategoryID');
select fx_event(:'eventPendingActiveID', :'groupID', :'eventCategoryID');
select fx_event(:'eventPendingInactiveID', :'groupID', :'eventCategoryID');

-- Co-host rows in every non-pending status for the same event
insert into event_cohost (event_id, group_id, event_cohost_status_id, approved_at) values
    (:'eventNonPendingCohostsID', :'groupApprovedID', 'approved', current_timestamp),
    (:'eventNonPendingCohostsID', :'groupCanceledID', 'canceled', null),
    (:'eventNonPendingCohostsID', :'groupEventCanceledID', 'event-canceled', null),
    (:'eventNonPendingCohostsID', :'groupEventDeletedID', 'event-deleted', null),
    (:'eventNonPendingCohostsID', :'groupRejectedID', 'rejected', null),
    (:'eventNonPendingCohostsID', :'groupRemovedID', 'removed', null);

-- Pending co-host rows for an active and an inactive group
insert into event_cohost (event_id, group_id, event_cohost_status_id) values
    (:'eventPendingActiveID', :'groupPendingActiveID', 'pending'),
    (:'eventPendingInactiveID', :'groupPendingInactiveID', 'pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false when the event has no co-host rows
select is(
    event_has_pending_cohosts(:'eventNoCohostsID'::uuid),
    false,
    'Should return false when the event has no co-host rows'
);

-- Should return false when the event only has non-pending co-host rows
select is(
    event_has_pending_cohosts(:'eventNonPendingCohostsID'::uuid),
    false,
    'Should return false when the event only has non-pending co-host rows'
);

-- Should return true when an active group is pending
select is(
    event_has_pending_cohosts(:'eventPendingActiveID'::uuid),
    true,
    'Should return true when an active group is pending'
);

-- Should return true when an inactive group is pending
select is(
    event_has_pending_cohosts(:'eventPendingInactiveID'::uuid),
    true,
    'Should return true when an inactive group is pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
