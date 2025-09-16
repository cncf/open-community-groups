-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set nonExistentCommunityID '00000000-0000-0000-0000-999999999999'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values
    (:'category1ID', 'Technology', :'community1ID'),
    (:'category2ID', 'Business', :'community1ID');

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
    created_at
) values
    (:'group1ID', 'Kubernetes Meetup', 'kubernetes-meetup', :'community1ID', :'category1ID',
     array['kubernetes', 'cloud'], 'San Francisco', 'CA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.4194 37.7749)'), 'SF Bay Area Kubernetes enthusiasts',
     'https://example.com/k8s-logo.png', '2024-01-03 10:00:00+00'),
    (:'group2ID', 'Docker Users', 'docker-users', :'community1ID', :'category1ID',
     array['docker', 'containers'], 'New York', 'NY', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-74.0060 40.7128)'), 'NYC Docker community meetup group',
     'https://example.com/docker-logo.png', '2024-01-02 10:00:00+00'),
    (:'group3ID', 'Business Leaders', 'business-leaders', :'community1ID', :'category2ID',
     array['leadership', 'management'], 'London', null, 'GB', 'United Kingdom', null,
     ST_GeogFromText('POINT(-0.1278 51.5074)'), 'London business leadership forum',
     'https://example.com/business-logo.png', '2024-01-01 10:00:00+00'),
    (:'group4ID', 'Tech Innovators', 'tech-innovators', :'community1ID', :'category1ID',
     array['innovation', 'tech'], 'Austin', 'TX', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-97.7431 30.2672)'), 'This is a placeholder group.',
     'https://example.com/tech-logo.png', '2024-01-04 10:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: search_community_groups without filters should return all groups JSON
select is(
    (select groups from search_community_groups(:'community1ID'::uuid, '{}'::jsonb))::jsonb,
    '[
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704362400,
            "group_id": "00000000-0000-0000-0000-000000000034",
            "name": "Tech Innovators",
            "slug": "tech-innovators",
            "city": "Austin",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "This is a placeholder group.",
            "latitude": 30.2672,
            "logo_url": "https://example.com/tech-logo.png",
            "longitude": -97.7431,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "TX"
        },
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704276000,
            "group_id": "00000000-0000-0000-0000-000000000031",
            "name": "Kubernetes Meetup",
            "slug": "kubernetes-meetup",
            "city": "San Francisco",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "SF Bay Area Kubernetes enthusiasts",
            "latitude": 37.7749,
            "logo_url": "https://example.com/k8s-logo.png",
            "longitude": -122.4194,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "CA"
        },
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704189600,
            "group_id": "00000000-0000-0000-0000-000000000032",
            "name": "Docker Users",
            "slug": "docker-users",
            "city": "New York",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "NYC Docker community meetup group",
            "latitude": 40.7128,
            "logo_url": "https://example.com/docker-logo.png",
            "longitude": -74.006,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "NY"
        },
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000012",
                "name": "Business",
                "normalized_name": "business"
            },
            "created_at": 1704103200,
            "group_id": "00000000-0000-0000-0000-000000000033",
            "name": "Business Leaders",
            "slug": "business-leaders",
            "city": "London",
            "country_code": "GB",
            "country_name": "United Kingdom",
            "description_short": "London business leadership forum",
            "latitude": 51.5074,
            "logo_url": "https://example.com/business-logo.png",
            "longitude": -0.1278
        }
    ]'::jsonb,
    'search_community_groups without filters returns all active groups with correct JSON structure'
);

-- Test: search_community_groups should return correct total count
select is(
    (select total from search_community_groups(:'community1ID'::uuid, '{}'::jsonb)),
    4::bigint,
    'search_community_groups returns correct total count'
);

-- Test: search_community_groups with non-existing community should return zero total
select is(
    (select total from search_community_groups(:'nonExistentCommunityID'::uuid, '{}'::jsonb)),
    0::bigint,
    'search_community_groups with non-existing community returns zero total'
);

-- Test: search_community_groups category filter should return Business Leaders JSON
select is(
    (select groups from search_community_groups(:'community1ID'::uuid, '{"group_category":["business"]}'::jsonb))::jsonb,
    '[
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000012",
                "name": "Business",
                "normalized_name": "business"
            },
            "created_at": 1704103200,
            "group_id": "00000000-0000-0000-0000-000000000033",
            "name": "Business Leaders",
            "slug": "business-leaders",
            "city": "London",
            "country_code": "GB",
            "country_name": "United Kingdom",
            "description_short": "London business leadership forum",
            "latitude": 51.5074,
            "logo_url": "https://example.com/business-logo.png",
            "longitude": -0.1278
        }
    ]'::jsonb,
    'search_community_groups category filter returns expected group JSON'
);

-- Test: search_community_groups region filter should return expected groups JSON
select is(
    (select groups from search_community_groups(:'community1ID'::uuid, '{"region":["north-america"]}'::jsonb))::jsonb,
    '[
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704362400,
            "group_id": "00000000-0000-0000-0000-000000000034",
            "name": "Tech Innovators",
            "slug": "tech-innovators",
            "city": "Austin",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "This is a placeholder group.",
            "latitude": 30.2672,
            "logo_url": "https://example.com/tech-logo.png",
            "longitude": -97.7431,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "TX"
        },
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704276000,
            "group_id": "00000000-0000-0000-0000-000000000031",
            "name": "Kubernetes Meetup",
            "slug": "kubernetes-meetup",
            "city": "San Francisco",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "SF Bay Area Kubernetes enthusiasts",
            "latitude": 37.7749,
            "logo_url": "https://example.com/k8s-logo.png",
            "longitude": -122.4194,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "CA"
        },
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704189600,
            "group_id": "00000000-0000-0000-0000-000000000032",
            "name": "Docker Users",
            "slug": "docker-users",
            "city": "New York",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "NYC Docker community meetup group",
            "latitude": 40.7128,
            "logo_url": "https://example.com/docker-logo.png",
            "longitude": -74.006,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "NY"
        }
    ]'::jsonb,
    'search_community_groups region filter returns expected groups JSON'
);

-- Test: search_community_groups ts_query filter should return Docker Users JSON
select is(
    (select groups from search_community_groups(:'community1ID'::uuid, '{"ts_query":"Docker"}'::jsonb))::jsonb,
    '[
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704189600,
            "group_id": "00000000-0000-0000-0000-000000000032",
            "name": "Docker Users",
            "slug": "docker-users",
            "city": "New York",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "NYC Docker community meetup group",
            "latitude": 40.7128,
            "logo_url": "https://example.com/docker-logo.png",
            "longitude": -74.006,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "NY"
        }
    ]'::jsonb,
    'search_community_groups ts_query filter returns expected group JSON'
);

-- Test: search_community_groups distance filter near Austin should return Tech Innovators
select is(
    (select groups from search_community_groups(
        :'community1ID'::uuid,
        '{"latitude":30.2672, "longitude":-97.7431, "distance":1000}'::jsonb
     ))::jsonb,
    '[
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704362400,
            "group_id": "00000000-0000-0000-0000-000000000034",
            "name": "Tech Innovators",
            "slug": "tech-innovators",
            "city": "Austin",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "This is a placeholder group.",
            "latitude": 30.2672,
            "logo_url": "https://example.com/tech-logo.png",
            "longitude": -97.7431,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "TX"
        }
    ]'::jsonb,
    'search_community_groups distance filter returns expected group JSON'
);

-- Test: search_community_groups pagination should return the second group JSON
select is(
    (select groups from search_community_groups(:'community1ID'::uuid, '{"limit":1, "offset":1}'::jsonb))::jsonb,
    '[
        {
            "active": true,
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1704276000,
            "group_id": "00000000-0000-0000-0000-000000000031",
            "name": "Kubernetes Meetup",
            "slug": "kubernetes-meetup",
            "city": "San Francisco",
            "country_code": "US",
            "country_name": "United States",
            "description_short": "SF Bay Area Kubernetes enthusiasts",
            "latitude": 37.7749,
            "logo_url": "https://example.com/k8s-logo.png",
            "longitude": -122.4194,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "state": "CA"
        }
    ]'::jsonb,
    'search_community_groups pagination returns expected group JSON'
);

-- Test: search_community_groups include_bbox should return expected bbox
select is(
    (select bbox from search_community_groups(:'community1ID'::uuid, '{"include_bbox":true}'::jsonb))::jsonb,
    '{"ne_lat": 51.5074, "ne_lon": -0.1278, "sw_lat": 30.2672, "sw_lon": -122.4194}'::jsonb,
    'search_community_groups include_bbox returns expected bbox'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
