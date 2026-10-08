-- Tests returning the summary of publicly visible groups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5ea60000-0000-0000-0000-000000000001'
\set deletedGroupID '5ea60000-0000-0000-0000-000000000002'
\set groupCategoryID '5ea60000-0000-0000-0000-000000000003'
\set groupID '5ea60000-0000-0000-0000-000000000004'
\set inactiveCommunityGroupCategoryID '5ea60000-0000-0000-0000-000000000005'
\set inactiveCommunityGroupID '5ea60000-0000-0000-0000-000000000006'
\set inactiveCommunityID '5ea60000-0000-0000-0000-000000000007'
\set inactiveGroupID '5ea60000-0000-0000-0000-000000000008'
\set unknownGroupID '5ea60000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community owning the groups
select fx_community(:'communityID', jsonb_build_object('active', true));

-- Inactive community
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Active group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Deleted group
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Active group of the inactive community
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityGroupCategoryID', jsonb_build_object(
    'active', true
));

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null for a deleted group
select is(
    get_public_group_summary(:'deletedGroupID'::uuid)::jsonb,
    null,
    'Should return null for a deleted group'
);

-- Should return null for a group of an inactive community
select is(
    get_public_group_summary(:'inactiveCommunityGroupID'::uuid)::jsonb,
    null,
    'Should return null for a group of an inactive community'
);

-- Should return null for an inactive group
select is(
    get_public_group_summary(:'inactiveGroupID'::uuid)::jsonb,
    null,
    'Should return null for an inactive group'
);

-- Should return null for an unknown group
select is(
    get_public_group_summary(:'unknownGroupID'::uuid)::jsonb,
    null,
    'Should return null for an unknown group'
);

-- Should return the summary of a public group
select is(
    get_public_group_summary(:'groupID'::uuid)::jsonb,
    get_group_summary(:'communityID'::uuid, :'groupID'::uuid)::jsonb,
    'Should return the summary of a public group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
