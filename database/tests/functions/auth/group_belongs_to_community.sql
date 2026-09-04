-- Tests whether a group belongs to a community.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID 'a0100000-0000-0000-0000-000000000001'
\set communityID 'a0100000-0000-0000-0000-000000000002'
\set deletedGroupID 'a0100000-0000-0000-0000-000000000003'
\set groupCategoryID 'a0100000-0000-0000-0000-000000000004'
\set missingGroupID 'a0100000-0000-0000-0000-000000000005'
\set otherCommunityID 'a0100000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, category and active group used by group ownership checks
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID');

-- Soft-deleted group owned by the community
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'deleted_at', current_timestamp
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false for a deleted group
select is(
    group_belongs_to_community(:'communityID'::uuid, :'deletedGroupID'::uuid),
    false,
    'Should return false for a deleted group'
);

-- Should return false for a group of another community
select is(
    group_belongs_to_community(:'otherCommunityID'::uuid, :'activeGroupID'::uuid),
    false,
    'Should return false for a group of another community'
);

-- Should return false for a missing group
select is(
    group_belongs_to_community(:'communityID'::uuid, :'missingGroupID'::uuid),
    false,
    'Should return false for a missing group'
);

-- Should return true for an active group of the community
select is(
    group_belongs_to_community(:'communityID'::uuid, :'activeGroupID'::uuid),
    true,
    'Should return true for an active group of the community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
