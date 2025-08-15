-- Start transaction and plan tests
begin;
select plan(2);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'

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
insert into group_category (group_category_id, name, community_id, "order")
values
    (:'category1ID', 'Technology', :'community1ID', 1),
    (:'category2ID', 'Business', :'community1ID', 2);

-- Seed regions
insert into region (region_id, name, community_id, "order")
values
    (:'region1ID', 'North America', :'community1ID', 1),
    (:'region2ID', 'Europe', :'community1ID', 2);

-- Seed event categories
insert into event_category (event_category_id, name, slug, community_id, "order")
values
    ('00000000-0000-0000-0000-000000000061', 'Tech Talks', 'tech-talks', :'community1ID', 1),
    ('00000000-0000-0000-0000-000000000062', 'Workshops', 'workshops', :'community1ID', 2),
    ('00000000-0000-0000-0000-000000000063', 'Conferences', 'conferences', :'community1ID', 3);

-- Test get_community_filters_options function returns correct data
select is(
    get_community_filters_options('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '{
        "region": [
            {"name": "North America", "value": "north-america"},
            {"name": "Europe", "value": "europe"}
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [
            {"name": "Tech Talks", "value": "tech-talks"},
            {"name": "Workshops", "value": "workshops"},
            {"name": "Conferences", "value": "conferences"}
        ],
        "group_category": [
            {"name": "Technology", "value": "technology"},
            {"name": "Business", "value": "business"}
        ]
    }'::jsonb,
    'get_community_filters_options should return correct filter options as JSON'
);

-- Test get_community_filters_options with non-existing community
select is(
    get_community_filters_options('00000000-0000-0000-0000-999999999999'::uuid)::jsonb,
    '{
        "region": [],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [],
        "group_category": []
    }'::jsonb,
    'get_community_filters_options with non-existing community should return default options'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;