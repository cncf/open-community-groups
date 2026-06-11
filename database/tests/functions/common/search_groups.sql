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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'community1ID',
        'test-community',
        'Test Community',
        'A test community',
        'https://example.com/banner_mobile.png',
        'https://example.com/banner.png',
        'https://example.com/logo.png'
    ),
    (
        :'community2ID',
        'other-community',
        'Other Community',
        'Another test community',
        'https://example.com/banner_mobile2.png',
        'https://example.com/banner2.png',
        'https://example.com/logo2.png'
    );

-- Inactive community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,

    active
) values (
    :'community3ID',
    'inactive-community',
    'Inactive Community',
    'An inactive test community',
    'https://example.com/banner_mobile3.png',
    'https://example.com/banner3.png',
    'https://example.com/logo3.png',

    false
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategory1ID', :'community1ID', 'Technology'),
    (:'groupCategory2ID', :'community1ID', 'Business'),
    (:'groupCategory3ID', :'community2ID', 'Technology'),
    (:'groupCategory4ID', :'community3ID', 'Technology');

-- Region
insert into region (region_id, community_id, name)
values (:'region1ID', :'community1ID', 'North America');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
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
    (:'group1ID', 'Kubernetes Meetup', 'abc1234', :'community1ID', :'groupCategory1ID',
     array['kubernetes', 'cloud'], 'San Francisco', 'CA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.4194 37.7749)'), 'SF Bay Area Kubernetes enthusiasts',
     'https://example.com/k8s-logo.png', true, '2024-01-03 10:00:00+00', false),
    (:'group2ID', 'Docker Users', 'def5678', :'community1ID', :'groupCategory1ID',
     array['docker', 'containers'], 'New York', 'NY', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-74.0060 40.7128)'), 'NYC Docker community meetup group',
     'https://example.com/docker-logo.png', true, '2024-01-02 10:00:00+00', false),
    (:'group3ID', 'Business Leaders', 'ghi9abc', :'community1ID', :'groupCategory2ID',
     array['leadership', 'management'], 'London', null, 'GB', 'United Kingdom', null,
     ST_GeogFromText('POINT(-0.1278 51.5074)'), 'London business leadership forum',
     'https://example.com/business-logo.png', true, '2024-01-01 10:00:00+00', false),
    (:'group4ID', 'Tech Innovators', 'jkl2def', :'community1ID', :'groupCategory1ID',
     array['innovation', 'tech'], 'Austin', 'TX', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-97.7431 30.2672)'), 'This is a placeholder group.',
     'https://example.com/tech-logo.png', true, '2024-01-04 10:00:00+00', false),
    (:'group5ID', 'Python Developers', 'mno3ghi', :'community2ID', :'groupCategory3ID',
     array['python', 'programming'], 'Chicago', 'IL', 'US', 'United States', null,
     ST_GeogFromText('POINT(-87.6298 41.8781)'), 'Chicago Python community meetup',
     'https://example.com/python-logo.png', true, '2024-01-05 10:00:00+00', false),
    (:'group6ID', 'Archived Group', 'pqr4jkl', :'community1ID', :'groupCategory2ID',
     array['archived'], 'Miami', 'FL', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-80.1918 25.7617)'), 'This group is inactive.',
     'https://example.com/archived-logo.png', false, '2024-01-06 10:00:00+00', false),
    (:'group7ID', 'Deleted Group', 'stu5mno', :'community1ID', :'groupCategory2ID',
     array['deleted'], 'Seattle', 'WA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.3321 47.6062)'), 'This group is soft deleted.',
     'https://example.com/deleted-logo.png', false, '2024-01-07 10:00:00+00', true),
    (:'group8ID', 'Inactive Community Group', 'vwx6pqr', :'community3ID', :'groupCategory4ID',
     array['inactive-community'], 'Denver', 'CO', 'US', 'United States', null,
     ST_GeogFromText('POINT(-104.9903 39.7392)'), 'This group belongs to an inactive community.',
     'https://example.com/inactive-community-logo.png', true, '2024-01-08 10:00:00+00', false);

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
        jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 10, 'offset', 0)
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
            search_groups(jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 10, 'offset', 0))::jsonb->>'total'
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
            'community', jsonb_build_array('test-community'),
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
            'community', jsonb_build_array('test-community'),
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
            'community', jsonb_build_array('test-community'),
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
            'community', jsonb_build_array('test-community'),
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
            'community', jsonb_build_array('test-community'),
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
        jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 1, 'offset', 1)
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
            'community', jsonb_build_array('test-community'),
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
            'community', jsonb_build_array('test-community'),
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
