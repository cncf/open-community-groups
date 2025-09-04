-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'

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
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'communityID');

-- Region
insert into region (region_id, name, community_id)
values
    (:'region1ID', 'North America', :'communityID'),
    (:'region2ID', 'Europe', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, created_at, logo_url, description,
                     city, state, country_code, country_name, region_id)
values
    (:'group1ID', 'Test Group 1', 'test-group-1', :'communityID', :'category1ID',
     '2024-01-01 09:00:00+00', 'https://example.com/logo1.png', 'First group',
     'New York', 'NY', 'US', 'United States', :'region1ID'),
    (:'group2ID', 'Test Group 2', 'test-group-2', :'communityID', :'category1ID',
     '2024-01-02 09:00:00+00', 'https://example.com/logo2.png', 'Second group',
     'San Francisco', 'CA', 'US', 'United States', :'region1ID'),
    (:'group3ID', 'Test Group 3', 'test-group-3', :'communityID', :'category1ID',
     '2024-01-03 09:00:00+00', 'https://example.com/logo3.png', 'Third group',
     'London', null, 'GB', 'United Kingdom', :'region2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- get_community_recently_added_groups function returns correct data
select is(
    get_community_recently_added_groups(:'communityID'::uuid)::jsonb,
    '[
        {
            "active": true,
            "city": "London",
            "name": "Test Group 3",
            "slug": "test-group-3",
            "group_id": "00000000-0000-0000-0000-000000000033",
            "logo_url": "https://example.com/logo3.png",
            "created_at": 1704272400,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000022",
                "name": "Europe",
                "normalized_name": "europe"
            },
            "country_code": "GB",
            "country_name": "United Kingdom",
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            }
        },
        {
            "active": true,
            "city": "San Francisco",
            "name": "Test Group 2",
            "slug": "test-group-2",
            "state": "CA",
            "group_id": "00000000-0000-0000-0000-000000000032",
            "logo_url": "https://example.com/logo2.png",
            "created_at": 1704186000,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "country_code": "US",
            "country_name": "United States",
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            }
        },
        {
            "active": true,
            "city": "New York",
            "name": "Test Group 1",
            "slug": "test-group-1",
            "state": "NY",
            "group_id": "00000000-0000-0000-0000-000000000031",
            "logo_url": "https://example.com/logo1.png",
            "created_at": 1704099600,
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000021",
                "name": "North America",
                "normalized_name": "north-america"
            },
            "country_code": "US",
            "country_name": "United States",
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            }
        }
    ]'::jsonb,
    'get_community_recently_added_groups should return groups ordered by creation date DESC as JSON'
);

-- get_community_recently_added_groups with non-existing community
select is(
    get_community_recently_added_groups('00000000-0000-0000-0000-999999999999'::uuid)::jsonb,
    '[]'::jsonb,
    'get_community_recently_added_groups with non-existing community should return empty array'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
