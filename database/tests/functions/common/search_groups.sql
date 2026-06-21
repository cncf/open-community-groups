-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'
\set category4ID '00000000-0000-0000-0000-000000000014'
\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set alliance3ID '00000000-0000-0000-0000-000000000003'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
\set group5ID '00000000-0000-0000-0000-000000000035'
\set group6ID '00000000-0000-0000-0000-000000000036'
\set group7ID '00000000-0000-0000-0000-000000000037'
\set group8ID '00000000-0000-0000-0000-000000000038'
\set nonExistentAllianceID '00000000-0000-0000-0000-999999999999'
\set region1ID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (
        :'alliance1ID',
        'test-alliance',
        'Test Alliance',
        'A test alliance',
        'https://example.com/logo.png',
        'https://example.com/banner_mobile.png',
        'https://example.com/banner.png'
    ),
    (
        :'alliance2ID',
        'other-alliance',
        'Other Alliance',
        'Another test alliance',
        'https://example.com/logo2.png',
        'https://example.com/banner_mobile2.png',
        'https://example.com/banner2.png'
    );

-- Inactive alliance
insert into alliance (
    alliance_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'alliance3ID',
    false,
    'inactive-alliance',
    'Inactive Alliance',
    'An inactive test alliance',
    'https://example.com/logo3.png',
    'https://example.com/banner_mobile3.png',
    'https://example.com/banner3.png'
);

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values
    (:'category1ID', 'Technology', :'alliance1ID'),
    (:'category2ID', 'Business', :'alliance1ID'),
    (:'category3ID', 'Technology', :'alliance2ID'),
    (:'category4ID', 'Technology', :'alliance3ID');

-- Region
insert into region (region_id, name, alliance_id)
values (:'region1ID', 'North America', :'alliance1ID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    alliance_id,
    group_category_id,
    tags,
    city,
    state,
    country_code,
    country_name,
    region_id,
    location,
    description_short,
    logo_url,
    active,
    created_at,
    deleted
) values
    (:'group1ID', 'Kubernetes Meetup', 'abc1234', :'alliance1ID', :'category1ID',
     array['kubernetes', 'cloud'], 'San Francisco', 'CA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.4194 37.7749)'), 'SF Bay Area Kubernetes enthusiasts',
     'https://example.com/k8s-logo.png', true, '2024-01-03 10:00:00+00', false),
    (:'group2ID', 'Docker Users', 'def5678', :'alliance1ID', :'category1ID',
     array['docker', 'containers'], 'New York', 'NY', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-74.0060 40.7128)'), 'NYC Docker alliance meetup group',
     'https://example.com/docker-logo.png', true, '2024-01-02 10:00:00+00', false),
    (:'group3ID', 'Business Leaders', 'ghi9abc', :'alliance1ID', :'category2ID',
     array['leadership', 'management'], 'London', null, 'GB', 'United Kingdom', null,
     ST_GeogFromText('POINT(-0.1278 51.5074)'), 'London business leadership forum',
     'https://example.com/business-logo.png', true, '2024-01-01 10:00:00+00', false),
    (:'group4ID', 'Tech Innovators', 'jkl2def', :'alliance1ID', :'category1ID',
     array['innovation', 'tech'], 'Austin', 'TX', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-97.7431 30.2672)'), 'This is a placeholder group.',
     'https://example.com/tech-logo.png', true, '2024-01-04 10:00:00+00', false),
    (:'group5ID', 'Python Developers', 'mno3ghi', :'alliance2ID', :'category3ID',
     array['python', 'programming'], 'Chicago', 'IL', 'US', 'United States', null,
     ST_GeogFromText('POINT(-87.6298 41.8781)'), 'Chicago Python alliance meetup',
     'https://example.com/python-logo.png', true, '2024-01-05 10:00:00+00', false),
    (:'group6ID', 'Archived Group', 'pqr4jkl', :'alliance1ID', :'category2ID',
     array['archived'], 'Miami', 'FL', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-80.1918 25.7617)'), 'This group is inactive.',
     'https://example.com/archived-logo.png', false, '2024-01-06 10:00:00+00', false),
    (:'group7ID', 'Deleted Group', 'stu5mno', :'alliance1ID', :'category2ID',
     array['deleted'], 'Seattle', 'WA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.3321 47.6062)'), 'This group is soft deleted.',
     'https://example.com/deleted-logo.png', false, '2024-01-07 10:00:00+00', true),
    (:'group8ID', 'Inactive Alliance Group', 'vwx6pqr', :'alliance3ID', :'category4ID',
     array['inactive-alliance'], 'Denver', 'CO', 'US', 'United States', null,
     ST_GeogFromText('POINT(-104.9903 39.7392)'), 'This group belongs to an inactive alliance.',
     'https://example.com/inactive-alliance-logo.png', true, '2024-01-08 10:00:00+00', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all active groups without filters
select is(
    (select search_groups(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'alliance2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should return all active groups without filters'
);

-- Should return inactive groups when include_inactive is enabled
select is(
    (select search_groups(jsonb_build_object('include_inactive', true, 'limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group6ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'alliance2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb
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

-- Should exclude groups from inactive alliances even when include_inactive is enabled
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_groups(jsonb_build_object('include_inactive', true, 'limit', 10, 'offset', 0))::jsonb->'groups'
        ) as g
        where g->>'group_id' = :'group8ID'
    ),
    'Should exclude groups from inactive alliances even when include_inactive is enabled'
);

-- Should filter groups by alliance
select is(
    (select search_groups(
        jsonb_build_object('alliance', jsonb_build_array('test-alliance'), 'limit', 10, 'offset', 0)
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by alliance'
);

-- Should return correct total count
select is(
    (
        select (
            search_groups(jsonb_build_object('alliance', jsonb_build_array('test-alliance'), 'limit', 10, 'offset', 0))::jsonb->>'total'
        )::bigint
    ),
    4::bigint,
    'Should return correct total count'
);

-- Should return zero total for non-existing alliance
select is(
    (
        select (
            search_groups(
                jsonb_build_object('alliance', jsonb_build_array('non-existent-alliance'), 'limit', 10, 'offset', 0)
            )::jsonb->>'total'
        )::bigint
    ),
    0::bigint,
    'Should return zero total for non-existing alliance'
);

-- Should return all groups when alliance filter is empty array
select is(
    (select search_groups(jsonb_build_object('alliance', jsonb_build_array(), 'limit', 10, 'offset', 0))::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group3ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'alliance2ID'::uuid, :'group5ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should return all groups when alliance filter is empty array'
);

-- Should filter groups by category
select is(
    (select search_groups(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'group_category', jsonb_build_array('business'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should filter groups by category'
);

-- Should filter groups by region
select is(
    (select search_groups(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'region', jsonb_build_array('north-america'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by region'
);

-- Should filter groups by text search query
select is(
    (select search_groups(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'ts_query', 'Docker',
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb
    ),
    'Should filter groups by text search query'
);

-- Should filter groups by distance
select is(
    (select search_groups(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'latitude', 30.2672,
            'longitude', -97.7431,
            'distance', 1000,
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by distance'
);

-- Should sort groups by distance
select is(
    (select search_groups(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'latitude', 37.7749,
            'longitude', -122.4194,
            'sort_by', 'distance',
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group4ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'alliance1ID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should sort groups by distance'
);

-- Should paginate results correctly
select is(
    (select search_groups(
        jsonb_build_object('alliance', jsonb_build_array('test-alliance'), 'limit', 1, 'offset', 1)
    )::jsonb->'groups'),
    jsonb_build_array(
        get_group_summary(:'alliance1ID'::uuid, :'group2ID'::uuid)::jsonb
    ),
    'Should paginate results correctly'
);

-- Include bbox option should return expected bbox
select is(
    (select search_groups(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
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
