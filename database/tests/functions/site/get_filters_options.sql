-- Tests returning global and community-specific explore filter options.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '9a010000-0000-0000-0000-000000000001'
\set community2ID '9a010000-0000-0000-0000-000000000002'
\set communityInactiveID '9a010000-0000-0000-0000-000000000012'
\set communityNoGroupsID '9a010000-0000-0000-0000-000000000013'
\set communityOnlyInactiveGroupID '9a010000-0000-0000-0000-000000000014'
\set eventCategory1ID '9a010000-0000-0000-0000-000000000003'
\set eventCategory2ID '9a010000-0000-0000-0000-000000000004'
\set eventCategory3ID '9a010000-0000-0000-0000-000000000005'
\set eventCategoryInactiveCommunityID '9a010000-0000-0000-0000-000000000015'
\set eventCategoryTieAlphaID '9a010000-0000-0000-0000-000000000016'
\set eventCategoryTieZetaID '9a010000-0000-0000-0000-000000000017'
\set group1ID '9a010000-0000-0000-0000-000000000006'
\set group2ID '9a010000-0000-0000-0000-000000000007'
\set groupCategory1ID '9a010000-0000-0000-0000-000000000008'
\set groupCategory2ID '9a010000-0000-0000-0000-000000000009'
\set groupCategoryInactiveCommunityID '9a010000-0000-0000-0000-000000000018'
\set groupCategoryOnlyInactiveID '9a010000-0000-0000-0000-000000000019'
\set groupCategoryTieAlphaID '9a010000-0000-0000-0000-00000000001a'
\set groupCategoryTieZetaID '9a010000-0000-0000-0000-00000000001b'
\set groupInactiveCommunityID '9a010000-0000-0000-0000-00000000001c'
\set groupOnlyInactiveID '9a010000-0000-0000-0000-00000000001d'
\set groupTieFirstID '9a010000-0000-0000-0000-00000000001e'
\set groupTieSecondID '9a010000-0000-0000-0000-00000000001f'
\set region1ID '9a010000-0000-0000-0000-000000000010'
\set region2ID '9a010000-0000-0000-0000-000000000011'
\set regionInactiveCommunityID '9a010000-0000-0000-0000-000000000020'
\set regionTieAlphaID '9a010000-0000-0000-0000-000000000021'
\set regionTieZetaID '9a010000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community whose filter options share display orders
select fx_community(:'community1ID', jsonb_build_object(
    'active', true,
    'display_name', 'Alpha Community',
    'name', 'alpha-community'
));

-- Active community returned with its filter options
select fx_community(:'community2ID', jsonb_build_object(
    'active', true,
    'display_name', 'Cloud Native Seattle Filters Options',
    'name', 'cloud-native-seattle-filters-options'
));

-- Inactive community whose filter options stay hidden
select fx_community(:'communityInactiveID', jsonb_build_object(
    'active', false,
    'name', 'inactive-community-filters-options'
));

-- Active community without groups
select fx_community(:'communityNoGroupsID', jsonb_build_object(
    'active', true,
    'name', 'no-groups-community-filters-options'
));

-- Active community whose only group is inactive
select fx_community(:'communityOnlyInactiveGroupID', jsonb_build_object(
    'active', true,
    'name', 'only-inactive-group-community-filters-options'
));

-- Event category ordered first for the selected community
select fx_event_category(:'eventCategory1ID', :'community2ID', jsonb_build_object(
    'name', 'Tech Talks',
    'order', 1
));

-- Event category ordered second for the selected community
select fx_event_category(:'eventCategory2ID', :'community2ID', jsonb_build_object(
    'name', 'Workshops',
    'order', 2
));

-- Event category ordered third for the selected community
select fx_event_category(:'eventCategory3ID', :'community2ID', jsonb_build_object(
    'name', 'Conferences',
    'order', 3
));

-- Event category hidden with its inactive community
select fx_event_category(:'eventCategoryInactiveCommunityID', :'communityInactiveID', jsonb_build_object(
    'name', 'Hidden Talks',
    'order', 1
));

-- Event category sharing its order, inserted before its name predecessor
select fx_event_category(:'eventCategoryTieZetaID', :'community1ID', jsonb_build_object(
    'name', 'Zeta Talks',
    'order', 1
));

-- Event category sharing its order, sorted first by name
select fx_event_category(:'eventCategoryTieAlphaID', :'community1ID', jsonb_build_object(
    'name', 'Alpha Talks',
    'order', 1
));

-- Group category ordered first for the selected community
select fx_group_category(:'groupCategory1ID', :'community2ID', jsonb_build_object(
    'name', 'Technology',
    'order', 1
));

-- Group category ordered second for the selected community
select fx_group_category(:'groupCategory2ID', :'community2ID', jsonb_build_object(
    'name', 'Business',
    'order', 2
));

-- Group category hidden with its inactive community
select fx_group_category(:'groupCategoryInactiveCommunityID', :'communityInactiveID', jsonb_build_object(
    'name', 'Hidden Category',
    'order', 1
));

-- Group category for the community whose only group is inactive
select fx_group_category(:'groupCategoryOnlyInactiveID', :'communityOnlyInactiveGroupID');

-- Group category sharing its order, inserted before its name predecessor
select fx_group_category(:'groupCategoryTieZetaID', :'community1ID', jsonb_build_object(
    'name', 'Zeta Category',
    'order', 1
));

-- Group category sharing its order, sorted first by name
select fx_group_category(:'groupCategoryTieAlphaID', :'community1ID', jsonb_build_object(
    'name', 'Alpha Category',
    'order', 1
));

-- Regions returned for the selected community
insert into region (region_id, name, community_id, "order")
values
    (:'region1ID', 'North America', :'community2ID', 1),
    (:'region2ID', 'Europe', :'community2ID', 2);

-- Region hidden with its inactive community
insert into region (region_id, name, community_id, "order")
values (:'regionInactiveCommunityID', 'Hidden Region', :'communityInactiveID', 1);

-- Regions sharing their order, the name successor inserted first
insert into region (region_id, name, community_id, "order")
values
    (:'regionTieZetaID', 'Zeta Region', :'community1ID', 1),
    (:'regionTieAlphaID', 'Alpha Region', :'community1ID', 1);

-- Group returned first as an event filter option
select fx_group(:'group1ID', :'community2ID', :'groupCategory1ID', jsonb_build_object(
    'active', true,
    'deleted', false,
    'name', 'Alpha Group',
    'slug', 'alpha-group',
    'slug_pretty', 'alpha-group-pretty'
));

-- Group returned second as an event filter option
select fx_group(:'group2ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'active', true,
    'deleted', false,
    'name', 'Beta Group',
    'slug', 'beta-group'
));

-- Active group hidden with its inactive community
select fx_group(:'groupInactiveCommunityID', :'communityInactiveID', :'groupCategoryInactiveCommunityID', jsonb_build_object(
    'active', true,
    'deleted', false,
    'name', 'Hidden Group',
    'slug', 'hidden-group'
));

-- Inactive group that does not list its community
select fx_group(:'groupOnlyInactiveID', :'communityOnlyInactiveGroupID', :'groupCategoryOnlyInactiveID', jsonb_build_object(
    'active', false
));

-- Group sharing its name, inserted before its lower identifier peer
select fx_group(:'groupTieSecondID', :'community1ID', :'groupCategoryTieAlphaID', jsonb_build_object(
    'active', true,
    'deleted', false,
    'name', 'Shared Name Group',
    'slug', 'shared-name-group-second'
));

-- Group sharing its name, sorted first by identifier
select fx_group(:'groupTieFirstID', :'community1ID', :'groupCategoryTieZetaID', jsonb_build_object(
    'active', true,
    'deleted', false,
    'name', 'Shared Name Group',
    'slug', 'shared-name-group-first'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not list communities without public groups
select is(
    get_filters_options()::jsonb -> 'communities',
    '[
        {"name": "Alpha Community", "value": "alpha-community"},
        {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
    ]'::jsonb,
    'Should not list communities without public groups'
);

-- Should not return groups when entity_kind is events but no community is provided
select is(
    get_filters_options(null, 'events')::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ]
    }'::jsonb,
    'Should not return groups when entity_kind is events but no community is provided'
);

-- Should order filter options sharing the same order by name
select is(
    get_filters_options('alpha-community', 'events')::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [
            {"name": "Alpha Talks", "value": "alpha-talks"},
            {"name": "Zeta Talks", "value": "zeta-talks"}
        ],
        "group_category": [
            {"name": "Alpha Category", "value": "alpha-category"},
            {"name": "Zeta Category", "value": "zeta-category"}
        ],
        "groups": [
            {"name": "Shared Name Group", "value": "shared-name-group-first"},
            {"name": "Shared Name Group", "value": "shared-name-group-second"}
        ],
        "region": [
            {"name": "Alpha Region", "value": "alpha-region"},
            {"name": "Zeta Region", "value": "zeta-region"}
        ]
    }'::jsonb,
    'Should order filter options sharing the same order by name'
);

-- Should return all filter options including groups when entity_kind is events
select is(
    get_filters_options('cloud-native-seattle-filters-options', 'events')::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [
            {"name": "Tech Talks", "value": "tech-talks"},
            {"name": "Workshops", "value": "workshops"},
            {"name": "Conferences", "value": "conferences"}
        ],
        "group_category": [
            {"name": "Technology", "value": "technology"},
            {"name": "Business", "value": "business"}
        ],
        "groups": [
            {"name": "Alpha Group", "value": "alpha-group-pretty"},
            {"name": "Beta Group", "value": "beta-group"}
        ],
        "region": [
            {"name": "North America", "value": "north-america"},
            {"name": "Europe", "value": "europe"}
        ]
    }'::jsonb,
    'Should return all filter options including groups when entity_kind is events'
);

-- Should return communities and distance options when no community_name is provided
select is(
    get_filters_options()::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ]
    }'::jsonb,
    'Should return communities and distance options when no community_name is provided'
);

-- Should return communities, distance and empty arrays for non-existing community
select is(
    get_filters_options('non-existent-community', 'events')::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [],
        "group_category": [],
        "groups": [],
        "region": []
    }'::jsonb,
    'Should return communities, distance and empty arrays for non-existing community'
);

-- Should return community filters but not groups when entity_kind is groups
select is(
    get_filters_options('cloud-native-seattle-filters-options', 'groups')::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [
            {"name": "Tech Talks", "value": "tech-talks"},
            {"name": "Workshops", "value": "workshops"},
            {"name": "Conferences", "value": "conferences"}
        ],
        "group_category": [
            {"name": "Technology", "value": "technology"},
            {"name": "Business", "value": "business"}
        ],
        "region": [
            {"name": "North America", "value": "north-america"},
            {"name": "Europe", "value": "europe"}
        ]
    }'::jsonb,
    'Should return community filters but not groups when entity_kind is groups'
);

-- Should return empty community filters for an inactive community
select is(
    get_filters_options('inactive-community-filters-options', 'events')::jsonb,
    '{
        "communities": [
            {"name": "Alpha Community", "value": "alpha-community"},
            {"name": "Cloud Native Seattle Filters Options", "value": "cloud-native-seattle-filters-options"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [],
        "group_category": [],
        "groups": [],
        "region": []
    }'::jsonb,
    'Should return empty community filters for an inactive community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
