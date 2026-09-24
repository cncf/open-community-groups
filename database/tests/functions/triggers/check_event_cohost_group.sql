-- Tests rejecting event groups as their own co-host.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e5100000-0000-0000-0000-000000000001'
\set eventCategoryID 'e5100000-0000-0000-0000-000000000002'
\set eventID 'e5100000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5100000-0000-0000-0000-000000000004'
\set groupID 'e5100000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and event
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a group co-hosting its own event
select throws_ok(
    format(
        'insert into event_cohost (event_id, group_id) values (%L::uuid, %L::uuid)',
        :'eventID',
        :'groupID'
    ),
    'event group cannot co-host its own event',
    'Should reject a group co-hosting its own event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
