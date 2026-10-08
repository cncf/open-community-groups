-- Tests listing the community contact filter options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alphaCategoryID '8a0e0000-0000-0000-0000-000000000004'
\set communityID '8a0e0000-0000-0000-0000-000000000001'
\set deletedGroupID '8a0e0000-0000-0000-0000-000000000016'
\set eastRegionID '8a0e0000-0000-0000-0000-000000000008'
\set emptyCategoryID '8a0e0000-0000-0000-0000-000000000005'
\set emptyCommunityID '8a0e0000-0000-0000-0000-000000000002'
\set foreignCategoryID '8a0e0000-0000-0000-0000-000000000007'
\set foreignCommunityID '8a0e0000-0000-0000-0000-000000000003'
\set foreignGroupID '8a0e0000-0000-0000-0000-000000000017'
\set foreignRegionID '8a0e0000-0000-0000-0000-000000000011'
\set inactiveGroupID '8a0e0000-0000-0000-0000-000000000015'
\set noRegionGroupID '8a0e0000-0000-0000-0000-000000000013'
\set regionGroupID '8a0e0000-0000-0000-0000-000000000012'
\set vacantRegionID '8a0e0000-0000-0000-0000-000000000009'
\set zetaCategoryID '8a0e0000-0000-0000-0000-000000000006'
\set zetaGroupID '8a0e0000-0000-0000-0000-000000000014'
\set zuluRegionID '8a0e0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose filter options are listed
select fx_community(:'communityID');

-- Community without group categories or regions
select fx_community(:'emptyCommunityID');

-- Community whose options are never listed
select fx_community(:'foreignCommunityID');

-- Unordered group category with active and unavailable groups
select fx_group_category(:'alphaCategoryID', :'communityID', jsonb_build_object('name', 'Alpha'));

-- Unordered group category without groups
select fx_group_category(:'emptyCategoryID', :'communityID', jsonb_build_object('name', 'Empty'));

-- Group category of the foreign community
select fx_group_category(:'foreignCategoryID', :'foreignCommunityID', jsonb_build_object('name', 'Foreign'));

-- Ordered group category listed first
select fx_group_category(
    :'zetaCategoryID',
    :'communityID',
    jsonb_build_object('name', 'Zeta', 'order', 1)
);

-- Unordered region with active and inactive groups
insert into region (region_id, community_id, name)
values (:'eastRegionID', :'communityID', 'East');

-- Region of the foreign community
insert into region (region_id, community_id, name)
values (:'foreignRegionID', :'foreignCommunityID', 'Foreign');

-- Unordered region without groups
insert into region (region_id, community_id, name)
values (:'vacantRegionID', :'communityID', 'Vacant');

-- Ordered region listed first
insert into region (region_id, community_id, name, "order")
values (:'zuluRegionID', :'communityID', 'Zulu', 1);

-- Deleted group without region, excluded from counts
select fx_group(
    :'deletedGroupID',
    :'communityID',
    :'alphaCategoryID',
    jsonb_build_object('active', false, 'deleted', true)
);

-- Group of the foreign community without region
select fx_group(:'foreignGroupID', :'foreignCommunityID', :'foreignCategoryID');

-- Inactive group in the east region, excluded from counts
select fx_group(
    :'inactiveGroupID',
    :'communityID',
    :'alphaCategoryID',
    jsonb_build_object('active', false, 'region_id', :'eastRegionID')
);

-- Active group without region
select fx_group(:'noRegionGroupID', :'communityID', :'alphaCategoryID');

-- Active group in the east region
select fx_group(:'regionGroupID', :'communityID', :'alphaCategoryID', jsonb_build_object('region_id', :'eastRegionID'));

-- Active group in the zulu region
select fx_group(:'zetaGroupID', :'communityID', :'zetaCategoryID', jsonb_build_object('region_id', :'zuluRegionID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty options for a community without categories or regions
select is(
    list_community_contact_filter_options(:'emptyCommunityID'::uuid)::jsonb,
    '{"group_categories": [], "no_region_groups_count": 0, "regions": []}'::jsonb,
    'Should return empty options for a community without categories or regions'
);

-- Should return options with active group counts in display order
select is(
    list_community_contact_filter_options(:'communityID'::uuid)::jsonb,
    jsonb_build_object(
        'group_categories', jsonb_build_array(
            jsonb_build_object('group_category_id', :'zetaCategoryID', 'groups_count', 1, 'name', 'Zeta'),
            jsonb_build_object('group_category_id', :'alphaCategoryID', 'groups_count', 2, 'name', 'Alpha'),
            jsonb_build_object('group_category_id', :'emptyCategoryID', 'groups_count', 0, 'name', 'Empty')
        ),
        'no_region_groups_count', 1,
        'regions', jsonb_build_array(
            jsonb_build_object('groups_count', 1, 'name', 'Zulu', 'region_id', :'zuluRegionID'),
            jsonb_build_object('groups_count', 1, 'name', 'East', 'region_id', :'eastRegionID'),
            jsonb_build_object('groups_count', 0, 'name', 'Vacant', 'region_id', :'vacantRegionID')
        )
    ),
    'Should return options with active group counts in display order'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
