-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'
\set region1ID '00000000-0000-0000-0000-000000000011'
\set region2ID '00000000-0000-0000-0000-000000000012'
\set region3ID '00000000-0000-0000-0000-000000000013'

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
    (:'community1ID', 'test-community-1', 'Test Community 1', 'test1.localhost', 'Test Community 1 Title', 'First test community', 'https://example.com/logo1.png', '{}'::jsonb),
    (:'community2ID', 'test-community-2', 'Test Community 2', 'test2.localhost', 'Test Community 2 Title', 'Second test community', 'https://example.com/logo2.png', '{}'::jsonb);

-- Seed regions for community 1
insert into region (region_id, name, community_id, "order")
values 
    (:'region1ID', 'North America', :'community1ID', 2),
    (:'region2ID', 'Europe', :'community1ID', 1);

-- Seed region for community 2 (different community)
insert into region (region_id, name, community_id)
values 
    (:'region3ID', 'Asia Pacific', :'community2ID');

-- Test: list_regions returns complete JSON array with proper ordering
select is(
    list_regions(:'community1ID'::uuid)::jsonb,
    '[
        {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "Europe",
            "normalized_name": "europe",
            "order": 1
        },
        {
            "region_id": "00000000-0000-0000-0000-000000000011",
            "name": "North America",
            "normalized_name": "north-america",
            "order": 2
        }
    ]'::jsonb,
    'list_regions should return complete region data ordered by order field, then by name'
);

-- Test: list_regions returns empty array for community with no regions
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
    :'community3ID'::uuid,
    'empty-community',
    'Empty Community',
    'empty.localhost',
    'Empty Community Title',
    'Community with no regions',
    'https://example.com/logo.png',
    '{}'::jsonb
);

select is(
    list_regions(:'community3ID'::uuid)::jsonb,
    '[]'::jsonb,
    'list_regions should return empty array for community with no regions'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;