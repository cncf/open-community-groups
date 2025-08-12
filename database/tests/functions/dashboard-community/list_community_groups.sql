-- Start transaction and plan tests
begin;
select plan(2);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set region1ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set group2ID '00000000-0000-0000-0000-000000000022'
\set group3ID '00000000-0000-0000-0000-000000000023'

-- Seed communities
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values 
    (
        :'community1ID',
        'test-community',
        'Test Community',
        'test.localhost',
        'Test Community Title',
        'A test community for testing purposes',
        'https://example.com/logo.png',
        '{}'::jsonb
    ),
    (
        :'community2ID',
        'other-community',
        'Other Community',
        'other.localhost',
        'Other Community Title',
        'Another test community',
        'https://example.com/logo2.png',
        '{}'::jsonb
    );

-- Seed group category
insert into group_category (group_category_id, name, "order", community_id)
values (:'category1ID', 'Technology', 1, :'community1ID');

-- Seed region
insert into region (region_id, name, "order", community_id)
values (:'region1ID', 'North America', 1, :'community1ID');

-- Seed groups for community1
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id,
    created_at,
    city,
    state,
    country_code,
    country_name,
    logo_url,
    region_id
) values 
    (
        :'group1ID',
        :'community1ID',
        'Alpha Group',
        'alpha-group',
        'First test group',
        :'category1ID',
        '2024-01-01 10:00:00'::timestamp,
        'San Francisco',
        'CA',
        'US',
        'United States',
        'https://example.com/alpha-logo.png',
        :'region1ID'
    ),
    (
        :'group2ID',
        :'community1ID',
        'Zeta Group',
        'zeta-group',
        'Second test group',
        :'category1ID',
        '2024-01-02 14:30:00'::timestamp,
        'New York',
        'NY',
        'US',
        'United States',
        null,
        null
    ),
    (
        :'group3ID',
        :'community2ID',
        'Other Community Group',
        'other-community-group',
        'Group in different community',
        :'category1ID',
        '2024-01-03 09:15:00'::timestamp,
        null,
        null,
        null,
        null,
        null,
        null
    );

-- Test list_community_groups returns empty array for community with no groups
select is(
    list_community_groups('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'list_community_groups should return empty array for community with no groups'
);

-- Test list_community_groups returns full JSON structure for groups ordered alphabetically
select is(
    list_community_groups(:'community1ID'::uuid)::jsonb,
    '[
        {
            "category": {
                "id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology",
                "order": 1
            },
            "created_at": 1704099600,
            "name": "Alpha Group",
            "slug": "alpha-group",
            "city": "San Francisco",
            "country_code": "US",
            "country_name": "United States",
            "logo_url": "https://example.com/alpha-logo.png",
            "region": {
                "id": "00000000-0000-0000-0000-000000000012",
                "name": "North America",
                "normalized_name": "north-america",
                "order": 1
            },
            "state": "CA"
        },
        {
            "category": {
                "id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology",
                "order": 1
            },
            "created_at": 1704202200,
            "name": "Zeta Group",
            "slug": "zeta-group",
            "city": "New York",
            "country_code": "US",
            "country_name": "United States",
            "state": "NY"
        }
    ]'::jsonb,
    'list_community_groups should return groups with full JSON structure ordered alphabetically by name'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;