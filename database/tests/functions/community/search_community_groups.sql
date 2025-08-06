-- Start transaction and plan tests
begin;
select plan(3);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'

-- Seed community
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

-- Seed group categories
insert into group_category (group_category_id, name, community_id)
values
    (:'category1ID', 'Technology', :'community1ID'),
    (:'category2ID', 'Business', :'community1ID');

-- Seed region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Seed groups
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
    description,
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
     'https://example.com/business-logo.png', '2024-01-01 10:00:00+00');

-- Test search without filters returns all groups with full JSON verification
select is(
    (select groups from search_community_groups('00000000-0000-0000-0000-000000000001'::uuid, '{}'::jsonb))::jsonb,
    '[
        {
            "category_name": "Technology",
            "created_at": 1704276000,
            "name": "Kubernetes Meetup",
            "slug": "kubernetes-meetup",
            "city": "San Francisco",
            "country_code": "US",
            "country_name": "United States",
            "description": "SF Bay Area Kubernetes enthusiasts",
            "latitude": 37.7749,
            "logo_url": "https://example.com/k8s-logo.png",
            "longitude": -122.4194,
            "region_name": "North America",
            "state": "CA"
        },
        {
            "category_name": "Technology",
            "created_at": 1704189600,
            "name": "Docker Users",
            "slug": "docker-users",
            "city": "New York",
            "country_code": "US",
            "country_name": "United States",
            "description": "NYC Docker community meetup group",
            "latitude": 40.7128,
            "logo_url": "https://example.com/docker-logo.png",
            "longitude": -74.006,
            "region_name": "North America",
            "state": "NY"
        },
        {
            "category_name": "Business",
            "created_at": 1704103200,
            "name": "Business Leaders",
            "slug": "business-leaders",
            "city": "London",
            "country_code": "GB",
            "country_name": "United Kingdom",
            "description": "London business leadership forum",
            "latitude": 51.5074,
            "logo_url": "https://example.com/business-logo.png",
            "longitude": -0.1278
        }
    ]'::jsonb,
    'search_community_groups without filters should return all active groups with correct JSON structure'
);

-- Test total count
select is(
    (select total from search_community_groups('00000000-0000-0000-0000-000000000001'::uuid, '{}'::jsonb)),
    3::bigint,
    'search_community_groups should return correct total count'
);

-- Test search with non-existing community
select is(
    (select total from search_community_groups('00000000-0000-0000-0000-999999999999'::uuid, '{}'::jsonb)),
    0::bigint,
    'search_community_groups with non-existing community should return zero total'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
