-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '0c170000-0000-0000-0000-000000000001'
\set community2ID '0c170000-0000-0000-0000-000000000002'
\set community3ID '0c170000-0000-0000-0000-000000000003'
\set group1ID '0c170000-0000-0000-0000-000000000004'
\set group2ID '0c170000-0000-0000-0000-000000000005'
\set group3ID '0c170000-0000-0000-0000-000000000006'
\set group4ID '0c170000-0000-0000-0000-000000000007'
\set group5ID '0c170000-0000-0000-0000-000000000008'
\set group6ID '0c170000-0000-0000-0000-000000000009'
\set group7ID '0c170000-0000-0000-0000-00000000000a'
\set group8ID '0c170000-0000-0000-0000-00000000000b'
\set groupCategory1ID '0c170000-0000-0000-0000-00000000000c'
\set groupCategory2ID '0c170000-0000-0000-0000-00000000000d'
\set groupCategory3ID '0c170000-0000-0000-0000-00000000000e'
\set groupCategory4ID '0c170000-0000-0000-0000-00000000000f'
\set nonExistentCommunityID '0c170000-0000-0000-0000-000000000010'
\set region1ID '0c170000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

select fx_community(:'community1ID', jsonb_build_object('name', 'test-community-search-groups'));

-- Inactive community
select fx_community(:'community3ID', jsonb_build_object(
    'active', false,
    'name', 'inactive-community-search-groups'
));

-- Baseline communities and group categories
select fx_community(:'community2ID');
select fx_group_category(:'groupCategory1ID', :'community1ID');
select fx_group_category(:'groupCategory3ID', :'community2ID');
select fx_group_category(:'groupCategory4ID', :'community3ID');

-- Group category used by group-category filtering
select fx_group_category(:'groupCategory2ID', :'community1ID', jsonb_build_object('name', 'Business'));

-- Region
insert into region (region_id, community_id, name)
values (:'region1ID', :'community1ID', 'North America');

-- Group
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-03 10:00:00+00',
    'description_short', 'SF Bay Area Kubernetes enthusiasts',
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'name', 'Kubernetes Meetup',
    'region_id', :'region1ID',
    'state', 'CA',
    'tags', array['kubernetes', 'cloud']
));
select fx_group(:'group2ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-02 10:00:00+00',
    'description_short', 'NYC Docker community meetup group',
    'location', ST_GeogFromText('POINT(-74.0060 40.7128)'),
    'name', 'Docker Users',
    'region_id', :'region1ID',
    'state', 'NY',
    'tags', array['docker', 'containers']
));
select fx_group(:'group3ID', :'community1ID', :'groupCategory2ID', jsonb_build_object(
    'city', 'London',
    'country_code', 'GB',
    'country_name', 'United Kingdom',
    'created_at', '2024-01-01 10:00:00+00',
    'description_short', 'London business leadership forum',
    'location', ST_GeogFromText('POINT(-0.1278 51.5074)'),
    'name', 'Business Leaders',
    'tags', array['leadership', 'management']
));
select fx_group(:'group4ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'Austin',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-04 10:00:00+00',
    'description_short', 'This is a placeholder group.',
    'location', ST_GeogFromText('POINT(-97.7431 30.2672)'),
    'name', 'Tech Innovators',
    'region_id', :'region1ID',
    'state', 'TX',
    'tags', array['innovation', 'tech']
));
select fx_group(:'group5ID', :'community2ID', :'groupCategory3ID', jsonb_build_object(
    'city', 'Chicago',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-05 10:00:00+00',
    'description_short', 'Chicago Python community meetup',
    'location', ST_GeogFromText('POINT(-87.6298 41.8781)'),
    'name', 'Python Developers',
    'state', 'IL',
    'tags', array['python', 'programming']
));
select fx_group(:'group6ID', :'community1ID', :'groupCategory2ID', jsonb_build_object(
    'active', false,
    'city', 'Miami',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-06 10:00:00+00',
    'description_short', 'This group is inactive.',
    'location', ST_GeogFromText('POINT(-80.1918 25.7617)'),
    'name', 'Archived Group',
    'region_id', :'region1ID',
    'state', 'FL',
    'tags', array['archived']
));
select fx_group(:'group7ID', :'community1ID', :'groupCategory2ID', jsonb_build_object(
    'active', false,
    'city', 'Seattle',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-07 10:00:00+00',
    'deleted', true,
    'description_short', 'This group is soft deleted.',
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'name', 'Deleted Group',
    'region_id', :'region1ID',
    'state', 'WA',
    'tags', array['deleted']
));
select fx_group(:'group8ID', :'community3ID', :'groupCategory4ID', jsonb_build_object(
    'city', 'Denver',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-08 10:00:00+00',
    'description_short', 'This group belongs to an inactive community.',
    'location', ST_GeogFromText('POINT(-104.9903 39.7392)'),
    'name', 'Inactive Community Group',
    'state', 'CO',
    'tags', array['inactive-community-search-groups']
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all active groups without filters
select is(
    (select search_groups(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should return all active groups without filters'
);

-- Should return inactive groups when include_inactive is enabled
select is(
    (select search_groups(jsonb_build_object('include_inactive', true, 'limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group6ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should return inactive groups when include_inactive is enabled'
);

-- Should exclude soft-deleted groups when include_inactive is enabled
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_groups(jsonb_build_object('include_inactive', true, 'limit', 10, 'offset', 0))::jsonb->'groups'
        ) as g
        where g->>'group_id' = :'group7ID'
    ),
    'Should exclude soft-deleted groups when include_inactive is enabled'
);

-- Should exclude groups from inactive communities even when include_inactive is enabled
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_groups(jsonb_build_object('include_inactive', true, 'limit', 10, 'offset', 0))::jsonb->'groups'
        ) as g
        where g->>'group_id' = :'group8ID'
    ),
    'Should exclude groups from inactive communities even when include_inactive is enabled'
);

-- Should filter groups by community
select is(
    (select search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community-search-groups'), 'limit', 10, 'offset', 0)
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by community'
);

-- Should return correct total count
select is(
    (
        select (
            search_groups(jsonb_build_object('community', jsonb_build_array('test-community-search-groups'), 'limit', 10, 'offset', 0))::jsonb->>'total'
        )::bigint
    ),
    4::bigint,
    'Should return correct total count'
);

-- Should return zero total for non-existing community
select is(
    (
        select (
            search_groups(
                jsonb_build_object('community', jsonb_build_array('non-existent-community'), 'limit', 10, 'offset', 0)
            )::jsonb->>'total'
        )::bigint
    ),
    0::bigint,
    'Should return zero total for non-existing community'
);

-- Should return all groups when community filter is empty array
select is(
    (select search_groups(jsonb_build_object('community', jsonb_build_array(), 'limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should return all groups when community filter is empty array'
);

-- Should filter groups by category
select is(
    (select search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community-search-groups'),
            'group_category', jsonb_build_array('business'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should filter groups by category'
);

-- Should filter groups by region
select is(
    (select search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community-search-groups'),
            'region', jsonb_build_array('north-america'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by region'
);

-- Should filter groups by text search query
select is(
    (select search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community-search-groups'),
            'ts_query', 'Docker',
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb
    ),
    'Should filter groups by text search query'
);

-- Should filter groups by distance
select is(
    (select search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community-search-groups'),
            'latitude', 30.2672,
            'longitude', -97.7431,
            'distance', 1000,
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by distance'
);

-- Should sort groups by distance
select is(
    (select search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community-search-groups'),
            'latitude', 37.7749,
            'longitude', -122.4194,
            'sort_by', 'distance',
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should sort groups by distance'
);

-- Should return groups ordered by creation date when sort_by is date
select is(
    (select search_groups(
        jsonb_build_object(
            'limit', 10,
            'offset', 0,
            'sort_by', 'date'
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date when sort_by is date'
);

-- Should paginate results correctly
select is(
    (select search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community-search-groups'), 'limit', 1, 'offset', 1)
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb
    ),
    'Should paginate results correctly'
);

-- Should filter groups by bbox
select is(
    (select search_groups(
        jsonb_build_object(
            'bbox_ne_lat', 38.0,
            'bbox_ne_lon', -122.0,
            'bbox_sw_lat', 37.0,
            'bbox_sw_lon', -123.0,
            'community', jsonb_build_array('test-community-search-groups'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb
    ),
    'Should filter groups by bbox'
);

-- Include bbox option should return expected bbox
select is(
    (select search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community-search-groups'),
            'include_bbox', true,
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'bbox'),
    '{"ne_lat": 51.5074, "ne_lon": -0.1278, "sw_lat": 30.2672, "sw_lon": -122.4194}'::jsonb,
    'Include bbox option should return expected bbox'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
