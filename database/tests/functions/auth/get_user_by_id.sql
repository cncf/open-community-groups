-- Start transaction and plan tests
begin;
select plan(7);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0001-000000000001'

-- Seed community
insert into community (
    community_id,
    name,
    display_name,
    host,
    description,
    header_logo_url,
    theme,
    title
) values (
    :'community1ID',
    'Test Community',
    'Test Community',
    'test.example.com',
    'Test Community Description',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Test Community Title'
);

-- Seed user
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id,
    password
) values (
    :'user1ID',
    'test@example.com',
    'testuser',
    true,
    'Test User',
    'test_hash',
    :'community1ID',
    'hashed_password_here'
);

-- Seed a group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    '00000000-0000-0000-0000-000000000001'::uuid,
    :'community1ID',
    'Test Category'
);

-- Seed a group for testing team membership
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description,
    website_url,
    logo_url
) values (
    '00000000-0000-0000-0000-000000000001'::uuid,
    :'community1ID',
    '00000000-0000-0000-0000-000000000001'::uuid,
    'Test Group',
    'test-group',
    'Test Group Description',
    'https://example.com',
    'https://example.com/logo.png'
);

-- Add user to group team
insert into group_team (
    group_id,
    user_id,
    role
) values (
    '00000000-0000-0000-0000-000000000001'::uuid,
    :'user1ID',
    'Admin'
);

-- Add user to community team
insert into community_team (
    community_id,
    user_id,
    role
) values (
    :'community1ID',
    :'user1ID',
    'Admin'
);

-- Test: User found by ID (without password)
select is(
    get_user_by_id('00000000-0000-0000-0001-000000000001'::uuid, false)::jsonb,
    '{
        "auth_hash": "test_hash",
        "belongs_to_any_group_team": true,
        "belongs_to_community_team": true,
        "email": "test@example.com",
        "email_verified": true,
        "has_password": true,
        "name": "Test User",
        "user_id": "00000000-0000-0000-0001-000000000001",
        "username": "testuser"
    }'::jsonb,
    'Should return user without password when include_password is false'
);

-- Test: User found by ID (with password)
select is(
    get_user_by_id('00000000-0000-0000-0001-000000000001'::uuid, true)::jsonb,
    '{
        "auth_hash": "test_hash",
        "belongs_to_any_group_team": true,
        "belongs_to_community_team": true,
        "email": "test@example.com",
        "email_verified": true,
        "has_password": true,
        "name": "Test User",
        "password": "hashed_password_here",
        "user_id": "00000000-0000-0000-0001-000000000001",
        "username": "testuser"
    }'::jsonb,
    'Should return user with password when include_password is true'
);

-- Test: User not found
select is(
    get_user_by_id('00000000-0000-0000-0001-999999999999'::uuid, false)::jsonb,
    null::jsonb,
    'Should return null when ID does not exist'
);

-- Test: User without team memberships
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    '00000000-0000-0000-0001-000000000002'::uuid,
    'nogroups@example.com',
    'nogroupsuser',
    true,
    'No Groups User',
    'test_hash_2',
    :'community1ID'
);

select is(
    get_user_by_id('00000000-0000-0000-0001-000000000002'::uuid, false)::jsonb,
    '{
        "auth_hash": "test_hash_2",
        "belongs_to_any_group_team": false,
        "belongs_to_community_team": false,
        "email": "nogroups@example.com",
        "email_verified": true,
        "name": "No Groups User",
        "user_id": "00000000-0000-0000-0001-000000000002",
        "username": "nogroupsuser"
    }'::jsonb,
    'Should return user with false team membership fields when user has no team memberships'
);

-- Test: User in group team but not community team
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    '00000000-0000-0000-0001-000000000003'::uuid,
    'grouponly@example.com',
    'grouponlyuser',
    true,
    'Group Only User',
    'test_hash_3',
    :'community1ID'
);

insert into group_team (
    group_id,
    user_id,
    role
) values (
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0001-000000000003'::uuid,
    'Admin'
);

select is(
    get_user_by_id('00000000-0000-0000-0001-000000000003'::uuid, false)::jsonb,
    '{
        "auth_hash": "test_hash_3",
        "belongs_to_any_group_team": true,
        "belongs_to_community_team": false,
        "email": "grouponly@example.com",
        "email_verified": true,
        "name": "Group Only User",
        "user_id": "00000000-0000-0000-0001-000000000003",
        "username": "grouponlyuser"
    }'::jsonb,
    'Should return user with belongs_to_any_group_team=true and belongs_to_community_team=false when user is only in group team'
);

-- Test: User who is only in community team (not in any group team)
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    '00000000-0000-0000-0001-000000000004'::uuid,
    'communityonly@example.com',
    'communityonlyuser',
    true,
    'Community Only User',
    'test_hash_4',
    :'community1ID'
);

insert into community_team (
    community_id,
    user_id,
    role
) values (
    :'community1ID',
    '00000000-0000-0000-0001-000000000004'::uuid,
    'Admin'
);

select is(
    get_user_by_id('00000000-0000-0000-0001-000000000004'::uuid, false)::jsonb,
    '{
        "auth_hash": "test_hash_4",
        "belongs_to_any_group_team": true,
        "belongs_to_community_team": true,
        "email": "communityonly@example.com",
        "email_verified": true,
        "name": "Community Only User",
        "user_id": "00000000-0000-0000-0001-000000000004",
        "username": "communityonlyuser"
    }'::jsonb,
    'Should return user with belongs_to_any_group_team=true when user is only in community team'
);

-- Test: User who is in both community team and group team
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    '00000000-0000-0000-0001-000000000005'::uuid,
    'both@example.com',
    'bothuser',
    true,
    'Both Teams User',
    'test_hash_5',
    :'community1ID'
);

insert into group_team (
    group_id,
    user_id,
    role
) values (
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0001-000000000005'::uuid,
    'Member'
);

insert into community_team (
    community_id,
    user_id,
    role
) values (
    :'community1ID',
    '00000000-0000-0000-0001-000000000005'::uuid,
    'Member'
);

select is(
    get_user_by_id('00000000-0000-0000-0001-000000000005'::uuid, false)::jsonb,
    '{
        "auth_hash": "test_hash_5",
        "belongs_to_any_group_team": true,
        "belongs_to_community_team": true,
        "email": "both@example.com",
        "email_verified": true,
        "name": "Both Teams User",
        "user_id": "00000000-0000-0000-0001-000000000005",
        "username": "bothuser"
    }'::jsonb,
    'Should return user with both belongs_to_any_group_team=true and belongs_to_community_team=true when user is in both teams'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;