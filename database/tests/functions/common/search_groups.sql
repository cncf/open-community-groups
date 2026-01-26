-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
\set group5ID '00000000-0000-0000-0000-000000000035'
\set group6ID '00000000-0000-0000-0000-000000000036'
\set nonExistentCommunityID '00000000-0000-0000-0000-999999999999'
\set region1ID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (
        :'community1ID',
        'test-community',
        'Test Community',
        'A test community',
        'https://example.com/logo.png',
        'https://example.com/banner_mobile.png',
        'https://example.com/banner.png'
    ),
    (
        :'community2ID',
        'other-community',
        'Other Community',
        'Another test community',
        'https://example.com/logo2.png',
        'https://example.com/banner_mobile2.png',
        'https://example.com/banner2.png'
    );

-- Group Category
insert into group_category (group_category_id, name, community_id)
values
    (:'category1ID', 'Technology', :'community1ID'),
    (:'category2ID', 'Business', :'community1ID'),
    (:'category3ID', 'Technology', :'community2ID');

-- Region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

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
    created_at
) values
    (:'group1ID', 'Kubernetes Meetup', 'abc1234', :'community1ID', :'category1ID',
     array['kubernetes', 'cloud'], 'San Francisco', 'CA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.4194 37.7749)'), 'SF Bay Area Kubernetes enthusiasts',
     'https://example.com/k8s-logo.png', true, '2024-01-03 10:00:00+00'),
    (:'group2ID', 'Docker Users', 'def5678', :'community1ID', :'category1ID',
     array['docker', 'containers'], 'New York', 'NY', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-74.0060 40.7128)'), 'NYC Docker community meetup group',
     'https://example.com/docker-logo.png', true, '2024-01-02 10:00:00+00'),
    (:'group3ID', 'Business Leaders', 'ghi9abc', :'community1ID', :'category2ID',
     array['leadership', 'management'], 'London', null, 'GB', 'United Kingdom', null,
     ST_GeogFromText('POINT(-0.1278 51.5074)'), 'London business leadership forum',
     'https://example.com/business-logo.png', true, '2024-01-01 10:00:00+00'),
    (:'group4ID', 'Tech Innovators', 'jkl2def', :'community1ID', :'category1ID',
     array['innovation', 'tech'], 'Austin', 'TX', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-97.7431 30.2672)'), 'This is a placeholder group.',
     'https://example.com/tech-logo.png', true, '2024-01-04 10:00:00+00'),
    (:'group5ID', 'Python Developers', 'mno3ghi', :'community2ID', :'category3ID',
     array['python', 'programming'], 'Chicago', 'IL', 'US', 'United States', null,
     ST_GeogFromText('POINT(-87.6298 41.8781)'), 'Chicago Python community meetup',
     'https://example.com/python-logo.png', true, '2024-01-05 10:00:00+00'),
    (:'group6ID', 'Archived Group', 'pqr4jkl', :'community1ID', :'category2ID',
     array['archived'], 'Miami', 'FL', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-80.1918 25.7617)'), 'This group is inactive.',
     'https://example.com/archived-logo.png', false, '2024-01-06 10:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all active groups without filters
select is(
    (select groups from search_groups('{}'::jsonb))::jsonb,
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
    (select groups from search_groups(jsonb_build_object('include_inactive', true)))::jsonb,
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

-- Should filter groups by community
select is(
    (select groups from search_groups(jsonb_build_object('community', jsonb_build_array('test-community'))))::jsonb,
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
    (select total from search_groups(jsonb_build_object('community', jsonb_build_array('test-community')))),
    4::bigint,
    'Should return correct total count'
);

-- Should return zero total for non-existing community
select is(
    (select total from search_groups(jsonb_build_object('community', jsonb_build_array('non-existent-community')))),
    0::bigint,
    'Should return zero total for non-existing community'
);

-- Should return all groups when community filter is empty array
select is(
    (select groups from search_groups(jsonb_build_object('community', jsonb_build_array())))::jsonb,
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
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'group_category', jsonb_build_array('business'))
    ))::jsonb,
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group3ID'::uuid)::jsonb
    ),
    'Should filter groups by category'
);

-- Should filter groups by region
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'region', jsonb_build_array('north-america'))
    ))::jsonb,
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group1ID'::uuid)::jsonb,
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by region'
);

-- Should filter groups by text search query
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'ts_query', 'Docker')
    ))::jsonb,
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb
    ),
    'Should filter groups by text search query'
);

-- Should filter groups by distance
select is(
    (select groups from search_groups(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'latitude', 30.2672,
            'longitude', -97.7431,
            'distance', 1000
        )
    ))::jsonb,
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group4ID'::uuid)::jsonb
    ),
    'Should filter groups by distance'
);

-- Should paginate results correctly
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 1, 'offset', 1)
    ))::jsonb,
    jsonb_build_array(
        get_group_summary(:'community1ID'::uuid, :'group2ID'::uuid)::jsonb
    ),
    'Should paginate results correctly'
);

-- Include bbox option should return expected bbox
select is(
    (select bbox from search_groups(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'include_bbox', true)
    ))::jsonb,
    '{"ne_lat": 51.5074, "ne_lon": -0.1278, "sw_lat": 30.2672, "sw_lon": -122.4194}'::jsonb,
    'Include bbox option should return expected bbox'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
