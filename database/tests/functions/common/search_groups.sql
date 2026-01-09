-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'
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
    logo_url
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/logo.png'
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
    (:'group1ID', 'Kubernetes Meetup', 'abc1234', :'community1ID', :'category1ID',
     array['kubernetes', 'cloud'], 'San Francisco', 'CA', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-122.4194 37.7749)'), 'SF Bay Area Kubernetes enthusiasts',
     'https://example.com/k8s-logo.png', '2024-01-03 10:00:00+00'),
    (:'group2ID', 'Docker Users', 'def5678', :'community1ID', :'category1ID',
     array['docker', 'containers'], 'New York', 'NY', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-74.0060 40.7128)'), 'NYC Docker community meetup group',
     'https://example.com/docker-logo.png', '2024-01-02 10:00:00+00'),
    (:'group3ID', 'Business Leaders', 'ghi9abc', :'community1ID', :'category2ID',
     array['leadership', 'management'], 'London', null, 'GB', 'United Kingdom', null,
     ST_GeogFromText('POINT(-0.1278 51.5074)'), 'London business leadership forum',
     'https://example.com/business-logo.png', '2024-01-01 10:00:00+00'),
    (:'group4ID', 'Tech Innovators', 'jkl2def', :'community1ID', :'category1ID',
     array['innovation', 'tech'], 'Austin', 'TX', 'US', 'United States', :'region1ID',
     ST_GeogFromText('POINT(-97.7431 30.2672)'), 'This is a placeholder group.',
     'https://example.com/tech-logo.png', '2024-01-04 10:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all active groups without filters
select is(
    (select groups from search_groups(jsonb_build_object('community', jsonb_build_array(:'community1ID'))))::jsonb,
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
            "slug": "jkl2def",
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
            "slug": "abc1234",
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
            "slug": "def5678",
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
            "slug": "ghi9abc",
            "city": "London",
            "country_code": "GB",
            "country_name": "United Kingdom",
            "description_short": "London business leadership forum",
            "latitude": 51.5074,
            "logo_url": "https://example.com/business-logo.png",
            "longitude": -0.1278
        }
    ]'::jsonb,
    'Should return all active groups without filters'
);

-- Should return correct total count
select is(
    (select total from search_groups(jsonb_build_object('community', jsonb_build_array(:'community1ID')))),
    4::bigint,
    'Should return correct total count'
);

-- Should return zero total for non-existing community
select is(
    (select total from search_groups(jsonb_build_object('community', jsonb_build_array(:'nonExistentCommunityID')))),
    0::bigint,
    'Should return zero total for non-existing community'
);

-- Category filter should return Business Leaders JSON
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array(:'community1ID'), 'group_category', jsonb_build_array('business'))
    ))::jsonb,
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
            "slug": "ghi9abc",
            "city": "London",
            "country_code": "GB",
            "country_name": "United Kingdom",
            "description_short": "London business leadership forum",
            "latitude": 51.5074,
            "logo_url": "https://example.com/business-logo.png",
            "longitude": -0.1278
        }
    ]'::jsonb,
    'Category filter should return expected group JSON'
);

-- Region filter should return expected groups JSON
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array(:'community1ID'), 'region', jsonb_build_array('north-america'))
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
            "slug": "jkl2def",
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
            "slug": "abc1234",
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
            "slug": "def5678",
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
    'Region filter should return expected groups JSON'
);

-- Text search filter should return Docker Users JSON
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array(:'community1ID'), 'ts_query', 'Docker')
    ))::jsonb,
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
            "slug": "def5678",
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
    'Text search filter should return expected group JSON'
);

-- Distance filter near Austin should return Tech Innovators
select is(
    (select groups from search_groups(
        jsonb_build_object(
            'community', jsonb_build_array(:'community1ID'),
            'latitude', 30.2672,
            'longitude', -97.7431,
            'distance', 1000
        )
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
            "slug": "jkl2def",
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
    'Distance filter should return expected group JSON'
);

-- Pagination should return the second group JSON
select is(
    (select groups from search_groups(
        jsonb_build_object('community', jsonb_build_array(:'community1ID'), 'limit', 1, 'offset', 1)
    ))::jsonb,
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
            "slug": "abc1234",
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
    'Pagination should return expected group JSON'
);

-- Include bbox option should return expected bbox
select is(
    (select bbox from search_groups(
        jsonb_build_object('community', jsonb_build_array(:'community1ID'), 'include_bbox', true)
    ))::jsonb,
    '{"ne_lat": 51.5074, "ne_lon": -0.1278, "sw_lat": 30.2672, "sw_lon": -122.4194}'::jsonb,
    'Include bbox option should return expected bbox'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
