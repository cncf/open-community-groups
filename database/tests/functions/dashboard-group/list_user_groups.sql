-- Start transaction and plan tests
begin;
select plan(4);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set groupMemberUserID '00000000-0000-0000-0000-000000000011'
\set regularUserID '00000000-0000-0000-0000-000000000012'
\set communityAdminUserID '00000000-0000-0000-0000-000000000013'
\set dualRoleUserID '00000000-0000-0000-0000-000000000014'
\set category1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set group4ID '00000000-0000-0000-0000-000000000034'

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
    (:'groupMemberUserID', gen_random_bytes(32), :'community1ID', 'groupmember@example.com', 'Group Member User', 'groupmember', true),
    (:'regularUserID', gen_random_bytes(32), :'community1ID', 'regular@example.com', 'Regular User', 'regularuser', true),
    (:'communityAdminUserID', gen_random_bytes(32), :'community1ID', 'communityadmin@example.com', 'Community Admin User', 'communityadmin', true),
    (:'dualRoleUserID', gen_random_bytes(32), :'community1ID', 'dualrole@example.com', 'Dual Role User', 'dualrole', true);

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

-- Seed groups (including one that will be deleted)
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
    (:'group3ID', :'community1ID', :'category1ID', 'Group C', 'group-c', '2024-01-03 10:00:00+00', 'Test City', 'US', 'United States'),
    (:'group4ID', :'community1ID', :'category1ID', 'Group D (Deleted)', 'group-d', '2024-01-04 10:00:00+00', 'Test City', 'US', 'United States');

-- Mark group4 as deleted (must also set active = false per check constraint)
update "group" set deleted = true, active = false where group_id = :'group4ID';

-- Group Member User: member of groups A and B only (not community team)
insert into group_team (group_id, user_id, role) values
    (:'group1ID', :'groupMemberUserID', 'organizer'),
    (:'group2ID', :'groupMemberUserID', 'member');

-- Community Admin User: community team member but not in any group teams
insert into community_team (community_id, user_id, role) values
    (:'community1ID', :'communityAdminUserID', 'Admin');

-- Dual Role User: both community team member AND group team member (of group B)
insert into community_team (community_id, user_id, role) values
    (:'community1ID', :'dualRoleUserID', 'Admin');
insert into group_team (group_id, user_id, role) values
    (:'group2ID', :'dualRoleUserID', 'member');

-- Test: Regular user (not in any teams) should see no groups
select is(
    list_user_groups(:'regularUserID'::uuid)::text,
    '[]',
    'Regular user without any team memberships should see empty array'
);

-- Test: Group team member (not community team) should see only their assigned groups
select is(
    list_user_groups(:'groupMemberUserID'::uuid)::jsonb,
    '[
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000021",
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
                "group_category_id": "00000000-0000-0000-0000-000000000021",
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
    'Group team member (not in community team) should see only groups A and B where they are members'
);

-- Test: Community team member (not in any group teams) should see all non-deleted groups
select is(
    list_user_groups(:'communityAdminUserID'::uuid)::jsonb,
    '[
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000021",
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
                "group_category_id": "00000000-0000-0000-0000-000000000021",
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
        },
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000021",
                "name": "Test Category",
                "normalized_name": "test-category",
                "order": 1
            },
            "created_at": 1704276000,
            "group_id": "00000000-0000-0000-0000-000000000033",
            "name": "Group C",
            "slug": "group-c",
            "city": "Test City",
            "country_code": "US",
            "country_name": "United States"
        }
    ]'::jsonb,
    'Community team member (not in any group teams) should see all three non-deleted groups (A, B, C)'
);

-- Test: User with both community team and group team membership should see all groups without duplicates
select is(
    list_user_groups(:'dualRoleUserID'::uuid)::jsonb,
    '[
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000021",
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
                "group_category_id": "00000000-0000-0000-0000-000000000021",
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
        },
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000021",
                "name": "Test Category",
                "normalized_name": "test-category",
                "order": 1
            },
            "created_at": 1704276000,
            "group_id": "00000000-0000-0000-0000-000000000033",
            "name": "Group C",
            "slug": "group-c",
            "city": "Test City",
            "country_code": "US",
            "country_name": "United States"
        }
    ]'::jsonb,
    'User with both community and group team roles should see all groups without duplicates (Group B not duplicated)'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
