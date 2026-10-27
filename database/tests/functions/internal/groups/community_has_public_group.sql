-- Tests checking whether a community has at least one publicly visible group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityNoGroupsID 'e10a0000-0000-0000-0000-000000000001'
\set communityOnlyInactiveGroupID 'e10a0000-0000-0000-0000-000000000002'
\set communityPublicGroupID 'e10a0000-0000-0000-0000-000000000003'
\set groupCategoryOnlyInactiveID 'e10a0000-0000-0000-0000-000000000004'
\set groupCategoryPublicID 'e10a0000-0000-0000-0000-000000000005'
\set groupInactiveID 'e10a0000-0000-0000-0000-000000000006'
\set groupPublicID 'e10a0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community without groups
select fx_community(:'communityNoGroupsID');

-- Community whose only group is inactive
select fx_community(:'communityOnlyInactiveGroupID');

-- Community with a public group
select fx_community(:'communityPublicGroupID');

-- Group category for the community with only an inactive group
select fx_group_category(:'groupCategoryOnlyInactiveID', :'communityOnlyInactiveGroupID');

-- Group category for the community with a public group
select fx_group_category(:'groupCategoryPublicID', :'communityPublicGroupID');

-- Inactive group that does not make its community visible
select fx_group(:'groupInactiveID', :'communityOnlyInactiveGroupID', :'groupCategoryOnlyInactiveID', jsonb_build_object(
    'active', false
));

-- Public group that makes its community visible
select fx_group(:'groupPublicID', :'communityPublicGroupID', :'groupCategoryPublicID', jsonb_build_object(
    'active', true,
    'deleted', false
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false for a community with no groups
select is(
    community_has_public_group(:'communityNoGroupsID'::uuid),
    false,
    'Should return false for a community with no groups'
);

-- Should return false for a community with only inactive groups
select is(
    community_has_public_group(:'communityOnlyInactiveGroupID'::uuid),
    false,
    'Should return false for a community with only inactive groups'
);

-- Should return true for a community with an active group
select is(
    community_has_public_group(:'communityPublicGroupID'::uuid),
    true,
    'Should return true for a community with an active group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
