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

-- Community that owns the groups
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Owner Community', '/logo', 'owner-community');

-- Community without groups
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'otherCommunityID', '/mobile', '/banner', 'Description', 'Other Community', '/logo', 'other-community');

-- Category used by the groups
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Active group owned by the community
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'activeGroupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group');

-- Soft-deleted group owned by the community
insert into "group" (group_id, community_id, group_category_id, active, deleted, deleted_at, name, slug)
values (:'deletedGroupID', :'communityID', :'groupCategoryID', false, true, current_timestamp, 'Deleted Group', 'deleted-group');

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
