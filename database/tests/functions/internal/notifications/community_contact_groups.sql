-- Tests listing the community groups the contact feature can reach.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '8a140000-0000-0000-0000-000000000003'
\set communityID '8a140000-0000-0000-0000-000000000001'
\set foreignCategoryID '8a140000-0000-0000-0000-000000000004'
\set foreignCommunityID '8a140000-0000-0000-0000-000000000002'
\set foreignGroupID '8a140000-0000-0000-0000-000000000014'
\set groupID '8a140000-0000-0000-0000-000000000011'
\set inactiveGroupID '8a140000-0000-0000-0000-000000000012'
\set regionID '8a140000-0000-0000-0000-000000000005'
\set subgroupID '8a140000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose groups are listed
select fx_community(:'communityID');

-- Community whose groups are never listed
select fx_community(:'foreignCommunityID');

-- Group category of the community
select fx_group_category(:'categoryID', :'communityID');

-- Group category of the foreign community
select fx_group_category(:'foreignCategoryID', :'foreignCommunityID');

-- Region of the community
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'North');

-- Active group of the foreign community
select fx_group(:'foreignGroupID', :'foreignCommunityID', :'foreignCategoryID');

-- Active group of the community in the region
select fx_group(:'groupID', :'communityID', :'categoryID', jsonb_build_object('region_id', :'regionID'));

-- Inactive group of the community
select fx_group(:'inactiveGroupID', :'communityID', :'categoryID', jsonb_build_object('active', false));

-- Active subgroup of the active group without region
select fx_group(:'subgroupID', :'communityID', :'categoryID', jsonb_build_object('parent_group_id', :'groupID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the active groups of the community with their category, parent and region
select results_eq(
    format(
        $$
            select group_category_id, group_id, parent_group_id, region_id
            from community_contact_groups(%L::uuid)
            order by group_id
        $$,
        :'communityID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid, null::uuid, %L::uuid),
            (%L::uuid, %L::uuid, %L::uuid, null::uuid)
        $$,
        :'categoryID', :'groupID', :'regionID',
        :'categoryID', :'subgroupID', :'groupID'
    ),
    'Should return the active groups of the community with their category, parent and region'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
