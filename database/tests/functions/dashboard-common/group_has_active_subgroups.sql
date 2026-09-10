-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeChildID '1c080000-0000-0000-0000-000000000001'
\set activeParentID '1c080000-0000-0000-0000-000000000002'
\set communityID '1c080000-0000-0000-0000-000000000003'
\set deletedChildID '1c080000-0000-0000-0000-000000000004'
\set deletedOnlyParentID '1c080000-0000-0000-0000-000000000005'
\set groupCategoryID '1c080000-0000-0000-0000-000000000006'
\set inactiveChildID '1c080000-0000-0000-0000-000000000007'
\set inactiveOnlyParentID '1c080000-0000-0000-0000-000000000008'
\set otherCommunityChildID '1c080000-0000-0000-0000-000000000009'
\set otherCommunityGroupCategoryID '1c080000-0000-0000-0000-00000000000a'
\set otherCommunityID '1c080000-0000-0000-0000-00000000000b'
\set otherCommunityParentID '1c080000-0000-0000-0000-00000000000c'
\set unrelatedGroupID '1c080000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group category and groups
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'otherCommunityGroupCategoryID', :'otherCommunityID');
select fx_group(:'activeParentID', :'communityID', :'groupCategoryID');
select fx_group(:'deletedOnlyParentID', :'communityID', :'groupCategoryID');
select fx_group(:'inactiveOnlyParentID', :'communityID', :'groupCategoryID');
select fx_group(:'otherCommunityParentID', :'otherCommunityID', :'otherCommunityGroupCategoryID');
select fx_group(:'unrelatedGroupID', :'communityID', :'groupCategoryID');

select fx_group(:'activeChildID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'activeParentID'));
-- group
select fx_group(:'deletedChildID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'parent_group_id', :'deletedOnlyParentID'
));
-- group
select fx_group(:'inactiveChildID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'parent_group_id', :'inactiveOnlyParentID'
));
-- group
select fx_group(:'otherCommunityChildID', :'otherCommunityID', :'otherCommunityGroupCategoryID', jsonb_build_object('parent_group_id', :'otherCommunityParentID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect active visible subgroups
select is(
    group_has_active_subgroups(:'communityID'::uuid, :'activeParentID'::uuid),
    true,
    'Should detect active visible subgroups'
);

-- Should ignore inactive children
select is(
    group_has_active_subgroups(:'communityID'::uuid, :'inactiveOnlyParentID'::uuid),
    false,
    'Should ignore inactive children'
);

-- Should ignore deleted children
select is(
    group_has_active_subgroups(:'communityID'::uuid, :'deletedOnlyParentID'::uuid),
    false,
    'Should ignore deleted children'
);

-- Should ignore child links from other communities
select is(
    group_has_active_subgroups(:'communityID'::uuid, :'otherCommunityParentID'::uuid),
    false,
    'Should ignore child links from other communities'
);

-- Should return false when there are no child links
select is(
    group_has_active_subgroups(:'communityID'::uuid, :'unrelatedGroupID'::uuid),
    false,
    'Should return false when there are no child links'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
