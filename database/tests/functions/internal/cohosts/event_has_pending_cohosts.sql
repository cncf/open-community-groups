-- Tests detecting pending event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5020000-0000-0000-0000-000000000001'
\set communityID 'e5020000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5020000-0000-0000-0000-000000000003'
\set eventID 'e5020000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5020000-0000-0000-0000-000000000005'
\set groupID 'e5020000-0000-0000-0000-000000000006'
\set missingEventID 'e5020000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and event
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Pending co-host invitation
insert into event_cohost (event_id, group_id)
values (:'eventID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false when no pending co-host exists
select is(
    event_has_pending_cohosts(:'missingEventID'::uuid),
    false,
    'Should return false when no pending co-host exists'
);

-- Should return true when a pending co-host exists
select is(
    event_has_pending_cohosts(:'eventID'::uuid),
    true,
    'Should return true when a pending co-host exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
