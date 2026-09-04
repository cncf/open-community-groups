-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '9a010000-0000-0000-0000-000000000001'
\set community2ID '9a010000-0000-0000-0000-000000000002'
\set eventCategory1ID '9a010000-0000-0000-0000-000000000003'
\set eventCategory2ID '9a010000-0000-0000-0000-000000000004'
\set eventCategory3ID '9a010000-0000-0000-0000-000000000005'
\set group1ID '9a010000-0000-0000-0000-000000000006'
\set group2ID '9a010000-0000-0000-0000-000000000007'
\set groupCategory1ID '9a010000-0000-0000-0000-000000000008'
\set groupCategory2ID '9a010000-0000-0000-0000-000000000009'
\set region1ID '9a010000-0000-0000-0000-000000000010'
\set region2ID '9a010000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities returned as global filter options
select fx_community(:'community1ID', jsonb_build_object(
    'display_name', 'Alpha Community',
    'name', 'alpha-community'
));
select fx_community(:'community2ID', jsonb_build_object(
    'display_name', 'Cloud Native Seattle Filters Options',
    'name', 'cloud-native-seattle-filters-options'
));

-- Group categories returned for the selected community
select fx_group_category(:'groupCategory1ID', :'community2ID', jsonb_build_object(
    'name', 'Technology',
    'order', 1
));
select fx_group_category(:'groupCategory2ID', :'community2ID', jsonb_build_object(
    'name', 'Business',
    'order', 2
));

-- Region
insert into region (region_id, name, community_id, "order")
values
    (:'region1ID', 'North America', :'community2ID', 1),
    (:'region2ID', 'Europe', :'community2ID', 2);

-- Event categories returned for the selected community
select fx_event_category(:'eventCategory1ID', :'community2ID', jsonb_build_object(
    'name', 'Tech Talks',
    'order', 1
));
select fx_event_category(:'eventCategory2ID', :'community2ID', jsonb_build_object(
    'name', 'Workshops',
    'order', 2
));
select fx_event_category(:'eventCategory3ID', :'community2ID', jsonb_build_object(
    'name', 'Conferences',
    'order', 3
));

-- Groups returned as event filter options
select fx_group(:'group1ID', :'community2ID', :'groupCategory1ID', jsonb_build_object(
    'name', 'Alpha Group',
    'slug', 'alpha-group',
    'slug_pretty', 'alpha-group-pretty'
));
select fx_group(:'group2ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'name', 'Beta Group',
    'slug', 'beta-group'
));

-- ============================================================================
-- TESTS
-- ============================================================================

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
