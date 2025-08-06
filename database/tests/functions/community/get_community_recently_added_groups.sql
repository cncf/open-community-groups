-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
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

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed groups with different creation times
insert into "group" (group_id, name, slug, community_id, group_category_id, created_at, logo_url, description)
values
    (:'group1ID', 'Test Group 1', 'test-group-1', :'community1ID', :'category1ID', 
     '2024-01-01 10:00:00', 'https://example.com/logo1.png', 'First group'),
    (:'group2ID', 'Test Group 2', 'test-group-2', :'community1ID', :'category1ID', 
     '2024-01-02 10:00:00', 'https://example.com/logo2.png', 'Second group'),
    (:'group3ID', 'Test Group 3', 'test-group-3', :'community1ID', :'category1ID', 
     '2024-01-03 10:00:00', 'https://example.com/logo3.png', 'Third group');

-- Test get_community_recently_added_groups function returns correct data
select is(
    get_community_recently_added_groups('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '[
        {
            "city": null,
            "name": "Test Group 3",
            "slug": "test-group-3",
            "state": null,
            "logo_url": "https://example.com/logo3.png",
            "created_at": 1704272400,
            "region_name": null,
            "country_code": null,
            "country_name": null,
            "category_name": "Technology"
        },
        {
            "city": null,
            "name": "Test Group 2",
            "slug": "test-group-2",
            "state": null,
            "logo_url": "https://example.com/logo2.png",
            "created_at": 1704186000,
            "region_name": null,
            "country_code": null,
            "country_name": null,
            "category_name": "Technology"
        },
        {
            "city": null,
            "name": "Test Group 1",
            "slug": "test-group-1",
            "state": null,
            "logo_url": "https://example.com/logo1.png",
            "created_at": 1704099600,
            "region_name": null,
            "country_code": null,
            "country_name": null,
            "category_name": "Technology"
        }
    ]'::jsonb,
    'get_community_recently_added_groups should return groups ordered by creation date DESC as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;