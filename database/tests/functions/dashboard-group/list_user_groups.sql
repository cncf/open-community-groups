-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set category1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'

-- Seed community
insert into community (
    community_id,
    display_name,
    host,
    name,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'Test Community',
    'test.example.com',
    'test-community',
    'Test Community Title',
    'Test Community Description',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed users
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    name,
    username,
    email_verified
) values
    (:'user1ID', gen_random_bytes(32), :'community1ID', 'user@example.com', 'Test User', 'testuser', true),
    (:'user2ID', gen_random_bytes(32), :'community1ID', 'user2@example.com', 'Test User 2', 'testuser2', true);

-- Seed group category
insert into group_category (
    group_category_id,
    community_id,
    name,
    "order"
) values (
    :'category1ID',
    :'community1ID',
    'Test Category',
    1
);

-- Seed groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    city,
    country_code,
    country_name
) values
    (:'group1ID', :'community1ID', :'category1ID', 'Group A', 'group-a', '2024-01-01 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group2ID', :'community1ID', :'category1ID', 'Group B', 'group-b', '2024-01-02 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group3ID', :'community1ID', :'category1ID', 'Group C', 'group-c', '2024-01-03 10:00:00+00', 'Test City', 'US', 'United States');

-- User 1 is only a member of groups A and B
insert into group_team (group_id, user_id, role) values
    (:'group1ID', :'user1ID', 'organizer'),
    (:'group2ID', :'user1ID', 'member');

-- Test: Function returns empty array for user with no groups
select is(
    list_user_groups(:'user2ID'::uuid)::text,
    '[]',
    'list_user_groups should return empty array for user with no groups'
);

-- Test: Function returns groups with full JSON structure ordered alphabetically
select is(
    list_user_groups(:'user1ID'::uuid)::jsonb,
    '[
        {
            "category": {
                "id": "00000000-0000-0000-0000-000000000021",
                "name": "Test Category",
                "normalized_name": "test-category",
                "order": 1
            },
            "created_at": 1704103200,
            "group_id": "00000000-0000-0000-0000-000000000031",
            "name": "Group A",
            "slug": "group-a",
            "city": "Test City",
            "country_code": "US",
            "country_name": "United States"
        },
        {
            "category": {
                "id": "00000000-0000-0000-0000-000000000021",
                "name": "Test Category",
                "normalized_name": "test-category",
                "order": 1
            },
            "created_at": 1704189600,
            "group_id": "00000000-0000-0000-0000-000000000032",
            "name": "Group B",
            "slug": "group-b",
            "city": "Test City",
            "country_code": "US",
            "country_name": "United States"
        }
    ]'::jsonb,
    'list_user_groups should return groups with full JSON structure ordered alphabetically by name'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
