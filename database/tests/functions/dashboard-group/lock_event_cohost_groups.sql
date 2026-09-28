-- Tests locking event co-host groups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5070000-0000-0000-0000-000000000001'
\set communityID 'e5070000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5070000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5070000-0000-0000-0000-000000000004'
\set groupID 'e5070000-0000-0000-0000-000000000005'
\set missingGroupID 'e5070000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Groups participating in an owner-side co-host edit
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock existing groups and ignore missing ids
select lives_ok(
    format(
        'select lock_event_cohost_groups(%L::uuid, array[%L::uuid, %L::uuid])',
        :'groupID',
        :'cohostGroupID',
        :'missingGroupID'
    ),
    'Should lock existing groups and ignore missing ids'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
