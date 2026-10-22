-- Tests locking groups that still accept dashboard mutations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f2030000-0000-0000-0000-000000000001'
\set deletedGroupID 'f2030000-0000-0000-0000-000000000002'
\set groupCategoryID 'f2030000-0000-0000-0000-000000000003'
\set inactiveGroupID 'f2030000-0000-0000-0000-000000000004'
\set liveGroupID 'f2030000-0000-0000-0000-000000000005'
\set missingGroupID 'f2030000-0000-0000-0000-000000000007'
\set otherCommunityID 'f2030000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and category
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Live group
select fx_group(:'liveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'name', 'Lock Active Group Live'
));

-- Deactivated group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false
));

-- Soft-deleted group
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'deleted_at', current_timestamp
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the group row
select is(
    (select (lock_active_group(:'communityID', :'liveGroupID')).name),
    'Lock Active Group Live',
    'Should return the group row'
);

-- Should return deactivated groups so they can be activated again
select is(
    (select (lock_active_group(:'communityID', :'inactiveGroupID')).active),
    false,
    'Should return deactivated groups so they can be activated again'
);

-- Should reject groups from another community
select throws_ok(
    format($$select lock_active_group(%L::uuid, %L::uuid)$$, :'otherCommunityID', :'liveGroupID'),
    'OCG01',
    'group not found or inactive',
    'Should reject groups from another community'
);

-- Should reject missing groups
select throws_ok(
    format($$select lock_active_group(%L::uuid, %L::uuid)$$, :'communityID', :'missingGroupID'),
    'OCG01',
    'group not found or inactive',
    'Should reject missing groups'
);

-- Should reject soft-deleted groups
select throws_ok(
    format($$select lock_active_group(%L::uuid, %L::uuid)$$, :'communityID', :'deletedGroupID'),
    'OCG01',
    'group not found or inactive',
    'Should reject soft-deleted groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
