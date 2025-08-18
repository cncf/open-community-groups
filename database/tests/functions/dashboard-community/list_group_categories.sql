-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'

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

-- Seed group categories for community 1
insert into group_category (group_category_id, name, community_id, "order")
values 
    (:'category1ID', 'Technology', :'community1ID', 2),
    (:'category2ID', 'Business', :'community1ID', 1);

-- Seed group category for community 2 (different community)
insert into group_category (group_category_id, name, community_id)
values 
    (:'category3ID', 'Education', :'community2ID');

-- Test: list_group_categories returns complete JSON array with proper ordering
select is(
    list_group_categories('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '[
        {
            "group_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Business",
            "slug": "business",
            "order": 1
        },
        {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "slug": "technology",
            "order": 2
        }
    ]'::jsonb,
    'list_group_categories should return complete category data ordered by order field, then by name'
);

-- Test: list_group_categories returns empty array for community with no categories
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
    '00000000-0000-0000-0000-000000000003'::uuid,
    'empty-community',
    'Empty Community',
    'empty.localhost',
    'Empty Community Title',
    'Community with no categories',
    'https://example.com/logo.png',
    '{}'::jsonb
);

select is(
    list_group_categories('00000000-0000-0000-0000-000000000003'::uuid)::jsonb,
    '[]'::jsonb,
    'list_group_categories should return empty array for community with no categories'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;