-- Tests searching groups.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '0c170000-0000-0000-0000-000000000001'
\set community2ID '0c170000-0000-0000-0000-000000000002'
\set communityTiesID '0c170000-0000-0000-0000-000000000012'
\set group1ID '0c170000-0000-0000-0000-000000000004'
\set group2ID '0c170000-0000-0000-0000-000000000005'
\set group3ID '0c170000-0000-0000-0000-000000000006'
\set group4ID '0c170000-0000-0000-0000-000000000007'
\set group5ID '0c170000-0000-0000-0000-000000000008'
\set groupCategory1ID '0c170000-0000-0000-0000-00000000000c'
\set groupCategory3ID '0c170000-0000-0000-0000-00000000000e'
\set groupCategoryTiesID '0c170000-0000-0000-0000-000000000013'
\set groupTieHighID '0c170000-0000-0000-0000-000000000015'
\set groupTieLowID '0c170000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community searched by name
select fx_community(:'community1ID', jsonb_build_object('name', 'test-community-search-groups'));

-- Second community
select fx_community(:'community2ID');

-- Community whose groups tie on every sort key but the group ID
select fx_community(:'communityTiesID', jsonb_build_object('name', 'ties-community-search-groups'));

-- Group category in the first community
select fx_group_category(:'groupCategory1ID', :'community1ID');

-- Group category in the second community
select fx_group_category(:'groupCategory3ID', :'community2ID');

-- Group category in the ties community
select fx_group_category(:'groupCategoryTiesID', :'communityTiesID');

-- Group in San Francisco
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-03 10:00:00+00',
    'description_short', 'SF Bay Area Kubernetes enthusiasts',
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'name', 'Kubernetes Meetup',
    'state', 'CA',
    'tags', array['kubernetes', 'cloud']
));

-- Group in New York
select fx_group(:'group2ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-02 10:00:00+00',
    'description_short', 'NYC Docker community meetup group',
    'location', ST_GeogFromText('POINT(-74.0060 40.7128)'),
    'name', 'Docker Users',
    'state', 'NY',
    'tags', array['docker', 'containers']
));

-- Group in London
select fx_group(:'group3ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'London',
    'country_code', 'GB',
    'country_name', 'United Kingdom',
    'created_at', '2024-01-01 10:00:00+00',
    'description_short', 'London business leadership forum',
    'location', ST_GeogFromText('POINT(-0.1278 51.5074)'),
    'name', 'Business Leaders',
    'tags', array['leadership', 'management']
));

-- Group in Austin
select fx_group(:'group4ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'Austin',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-04 10:00:00+00',
    'description_short', 'This is a placeholder group.',
    'location', ST_GeogFromText('POINT(-97.7431 30.2672)'),
    'name', 'Tech Innovators',
    'state', 'TX',
    'tags', array['innovation', 'tech']
));

-- Group in Chicago in the second community
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

-- Tied group with the higher group ID, inserted first
select fx_group(:'groupTieHighID', :'communityTiesID', :'groupCategoryTiesID', jsonb_build_object(
    'created_at', '2023-12-31 10:00:00+00',
    'name', 'Tied Group'
));

-- Tied group with the lower group ID, sharing the name and creation date
select fx_group(:'groupTieLowID', :'communityTiesID', :'groupCategoryTiesID', jsonb_build_object(
    'created_at', '2023-12-31 10:00:00+00',
    'name', 'Tied Group'
));

-- ============================================================================
-- TESTS
-- ============================================================================

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

-- Should paginate groups tied on name and creation date by group ID
select is(
    (
        select jsonb_agg(
            search_groups(jsonb_build_object(
                'community', jsonb_build_array('ties-community-search-groups'),
                'limit', 1,
                'offset', page_offset
            ))::jsonb->'groups'->0->>'group_id'
            order by page_offset
        )
        from generate_series(0, 1) as page_offset
    ),
    jsonb_build_array(:'groupTieLowID', :'groupTieHighID'),
    'Should paginate groups tied on name and creation date by group ID'
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

-- Should return all active groups without filters
select is(
    (select search_groups(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'communityTiesID'::uuid, :'groupTieLowID'::uuid)::jsonb,
        get_group_summary(:'communityTiesID'::uuid, :'groupTieHighID'::uuid)::jsonb
    ),
    'Should return all active groups without filters'
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
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'communityTiesID'::uuid, :'groupTieLowID'::uuid)::jsonb,
        get_group_summary(:'communityTiesID'::uuid, :'groupTieHighID'::uuid)::jsonb
    ),
    'Should return groups ordered by creation date when sort_by is date'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
