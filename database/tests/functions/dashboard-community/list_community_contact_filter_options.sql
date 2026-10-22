-- Tests listing the community contact filter options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeParentGroupID '8a0e0000-0000-0000-0000-000000000024'
\set activeSubgroupID '8a0e0000-0000-0000-0000-000000000025'
\set alphaCategoryID '8a0e0000-0000-0000-0000-000000000004'
\set communityID '8a0e0000-0000-0000-0000-000000000001'
\set deletedGroupID '8a0e0000-0000-0000-0000-000000000016'
\set deletedParentGroupID '8a0e0000-0000-0000-0000-000000000026'
\set deletedParentSubgroupID '8a0e0000-0000-0000-0000-000000000027'
\set deletedSubgroupID '8a0e0000-0000-0000-0000-000000000028'
\set eastRegionID '8a0e0000-0000-0000-0000-000000000008'
\set emptyCategoryID '8a0e0000-0000-0000-0000-000000000005'
\set emptyCommunityID '8a0e0000-0000-0000-0000-000000000002'
\set foreignCategoryID '8a0e0000-0000-0000-0000-000000000007'
\set foreignCommunityID '8a0e0000-0000-0000-0000-000000000003'
\set foreignGroupID '8a0e0000-0000-0000-0000-000000000017'
\set foreignRegionID '8a0e0000-0000-0000-0000-000000000011'
\set foreignSubgroupID '8a0e0000-0000-0000-0000-000000000029'
\set inactiveGroupID '8a0e0000-0000-0000-0000-000000000015'
\set inactiveParentGroupID '8a0e0000-0000-0000-0000-000000000030'
\set inactiveParentSubgroupID '8a0e0000-0000-0000-0000-000000000031'
\set inactiveSubgroupID '8a0e0000-0000-0000-0000-000000000032'
\set noRegionGroupID '8a0e0000-0000-0000-0000-000000000013'
\set regionGroupID '8a0e0000-0000-0000-0000-000000000012'
\set subgroupsCategoryID '8a0e0000-0000-0000-0000-000000000023'
\set subgroupsCommunityID '8a0e0000-0000-0000-0000-000000000020'
\set unavailableParentsCategoryID '8a0e0000-0000-0000-0000-000000000021'
\set unavailableParentsCommunityID '8a0e0000-0000-0000-0000-000000000018'
\set unavailableSubgroupsCategoryID '8a0e0000-0000-0000-0000-000000000022'
\set unavailableSubgroupsCommunityID '8a0e0000-0000-0000-0000-000000000019'
\set unavailableSubgroupsParentGroupID '8a0e0000-0000-0000-0000-000000000033'
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

-- Community with an active subgroup of an active parent group
select fx_community(:'subgroupsCommunityID');

-- Community whose active subgroups have inactive or deleted parent groups
select fx_community(:'unavailableParentsCommunityID');

-- Community whose subgroups are inactive or deleted
select fx_community(:'unavailableSubgroupsCommunityID');

-- Unordered group category with active and unavailable groups
select fx_group_category(:'alphaCategoryID', :'communityID', jsonb_build_object('name', 'Alpha'));

-- Unordered group category without groups
select fx_group_category(:'emptyCategoryID', :'communityID', jsonb_build_object('name', 'Empty'));

-- Group category of the foreign community
select fx_group_category(:'foreignCategoryID', :'foreignCommunityID', jsonb_build_object('name', 'Foreign'));

-- Group category of the community with an active subgroup
select fx_group_category(:'subgroupsCategoryID', :'subgroupsCommunityID');

-- Group category of the community with inactive or deleted parent groups
select fx_group_category(:'unavailableParentsCategoryID', :'unavailableParentsCommunityID');

-- Group category of the community with inactive or deleted subgroups
select fx_group_category(:'unavailableSubgroupsCategoryID', :'unavailableSubgroupsCommunityID');

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

-- Active parent group of the community with an active subgroup
select fx_group(:'activeParentGroupID', :'subgroupsCommunityID', :'subgroupsCategoryID');

-- Deleted group without region, excluded from counts and group options
select fx_group(
    :'deletedGroupID',
    :'communityID',
    :'alphaCategoryID',
    jsonb_build_object('active', false, 'deleted', true, 'name', 'Deleted')
);

-- Parent group deleted once its subgroup is linked
select fx_group(:'deletedParentGroupID', :'unavailableParentsCommunityID', :'unavailableParentsCategoryID');

-- Group of the foreign community without region, parent of its active subgroup
select fx_group(:'foreignGroupID', :'foreignCommunityID', :'foreignCategoryID');

-- Inactive group in the east region, excluded from counts and group options
select fx_group(
    :'inactiveGroupID',
    :'communityID',
    :'alphaCategoryID',
    jsonb_build_object('active', false, 'name', 'Inactive', 'region_id', :'eastRegionID')
);

-- Parent group deactivated once its subgroup is linked
select fx_group(:'inactiveParentGroupID', :'unavailableParentsCommunityID', :'unavailableParentsCategoryID');

-- Active group without region
select fx_group(:'noRegionGroupID', :'communityID', :'alphaCategoryID', jsonb_build_object('name', 'Rust'));

-- Active group in the east region
select fx_group(
    :'regionGroupID',
    :'communityID',
    :'alphaCategoryID',
    jsonb_build_object('name', 'Kubernetes', 'region_id', :'eastRegionID')
);

-- Active parent group of the inactive and deleted subgroups
select fx_group(
    :'unavailableSubgroupsParentGroupID',
    :'unavailableSubgroupsCommunityID',
    :'unavailableSubgroupsCategoryID'
);

-- Active group in the zulu region
select fx_group(
    :'zetaGroupID',
    :'communityID',
    :'zetaCategoryID',
    jsonb_build_object('name', 'Go', 'region_id', :'zuluRegionID')
);

-- Active subgroup of the active parent group
select fx_group(
    :'activeSubgroupID',
    :'subgroupsCommunityID',
    :'subgroupsCategoryID',
    jsonb_build_object('parent_group_id', :'activeParentGroupID')
);

-- Active subgroup of the parent group deleted below
select fx_group(
    :'deletedParentSubgroupID',
    :'unavailableParentsCommunityID',
    :'unavailableParentsCategoryID',
    jsonb_build_object('parent_group_id', :'deletedParentGroupID')
);

-- Deleted subgroup of an active parent group
select fx_group(
    :'deletedSubgroupID',
    :'unavailableSubgroupsCommunityID',
    :'unavailableSubgroupsCategoryID',
    jsonb_build_object(
        'active', false,
        'deleted', true,
        'parent_group_id', :'unavailableSubgroupsParentGroupID'
    )
);

-- Active subgroup of the foreign community, never flagged for other communities
select fx_group(
    :'foreignSubgroupID',
    :'foreignCommunityID',
    :'foreignCategoryID',
    jsonb_build_object('parent_group_id', :'foreignGroupID')
);

-- Active subgroup of the parent group deactivated below
select fx_group(
    :'inactiveParentSubgroupID',
    :'unavailableParentsCommunityID',
    :'unavailableParentsCategoryID',
    jsonb_build_object('parent_group_id', :'inactiveParentGroupID')
);

-- Inactive subgroup of an active parent group
select fx_group(
    :'inactiveSubgroupID',
    :'unavailableSubgroupsCommunityID',
    :'unavailableSubgroupsCategoryID',
    jsonb_build_object('active', false, 'parent_group_id', :'unavailableSubgroupsParentGroupID')
);

-- Delete the linked parent group, since the parent check rejects links to deleted parents
update "group"
set
    active = false,
    deleted = true
where group_id = :'deletedParentGroupID';

-- Deactivate the linked parent group, since the parent check rejects links to inactive parents
update "group"
set active = false
where group_id = :'inactiveParentGroupID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flag subgroups when an active group has an active parent group
select is(
    (list_community_contact_filter_options(:'subgroupsCommunityID'::uuid)::jsonb->>'has_subgroups')::boolean,
    true,
    'Should flag subgroups when an active group has an active parent group'
);

-- Should ignore inactive and deleted subgroups
select is(
    (list_community_contact_filter_options(:'unavailableSubgroupsCommunityID'::uuid)::jsonb->>'has_subgroups')::boolean,
    false,
    'Should ignore inactive and deleted subgroups'
);

-- Should ignore subgroups of inactive and deleted parent groups
select is(
    (list_community_contact_filter_options(:'unavailableParentsCommunityID'::uuid)::jsonb->>'has_subgroups')::boolean,
    false,
    'Should ignore subgroups of inactive and deleted parent groups'
);

-- Should ignore subgroups of other communities
select is(
    (list_community_contact_filter_options(:'communityID'::uuid)::jsonb->>'has_subgroups')::boolean,
    false,
    'Should ignore subgroups of other communities'
);

-- Should return empty options for a community without groups, categories or regions
select is(
    list_community_contact_filter_options(:'emptyCommunityID'::uuid)::jsonb,
    '{"group_categories": [], "groups": [], "has_subgroups": false, "no_region_groups_count": 0, "regions": []}'::jsonb,
    'Should return empty options for a community without groups, categories or regions'
);

-- Should return options with active groups labeled and counted in display order
select is(
    list_community_contact_filter_options(:'communityID'::uuid)::jsonb,
    jsonb_build_object(
        'group_categories', jsonb_build_array(
            jsonb_build_object('group_category_id', :'zetaCategoryID', 'groups_count', 1, 'name', 'Zeta'),
            jsonb_build_object('group_category_id', :'alphaCategoryID', 'groups_count', 2, 'name', 'Alpha'),
            jsonb_build_object('group_category_id', :'emptyCategoryID', 'groups_count', 0, 'name', 'Empty')
        ),
        'groups', jsonb_build_array(
            jsonb_build_object('group_id', :'zetaGroupID', 'label', 'Go · Zeta · Zulu'),
            jsonb_build_object('group_id', :'regionGroupID', 'label', 'Kubernetes · Alpha · East'),
            jsonb_build_object('group_id', :'noRegionGroupID', 'label', 'Rust · Alpha')
        ),
        'has_subgroups', false,
        'no_region_groups_count', 1,
        'regions', jsonb_build_array(
            jsonb_build_object('groups_count', 1, 'name', 'Zulu', 'region_id', :'zuluRegionID'),
            jsonb_build_object('groups_count', 1, 'name', 'East', 'region_id', :'eastRegionID'),
            jsonb_build_object('groups_count', 0, 'name', 'Vacant', 'region_id', :'vacantRegionID')
        )
    ),
    'Should return options with active groups labeled and counted in display order'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
