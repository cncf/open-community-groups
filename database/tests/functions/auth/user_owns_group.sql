-- Start transaction and plan tests
begin;
select plan(3);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'

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

-- Seed users
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    :'user1ID',
    gen_random_bytes(32),
    :'community1ID',
    'user1@example.com',
    true,
    'User One',
    'userone'
), (
    :'user2ID',
    gen_random_bytes(32),
    :'community1ID',
    'user2@example.com',
    true,
    'User Two',
    'usertwo'
);

-- Seed group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    '00000000-0000-0000-0000-000000000031',
    :'community1ID',
    'Test Category'
);

-- Seed group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'group1ID',
    :'community1ID',
    '00000000-0000-0000-0000-000000000031',
    'Test Group',
    'test-group',
    'Test Group Description'
);

-- Add user1 to group team
insert into group_team (
    group_id,
    user_id,
    role
) values (
    :'group1ID',
    :'user1ID',
    'Organizer'
);

-- Test: User who is in group_team should own the group
select ok(
    user_owns_group(:'user1ID', :'group1ID'),
    'User in group_team should own the group'
);

-- Test: User who is not in group_team should not own the group
select ok(
    not user_owns_group(:'user2ID', :'group1ID'),
    'User not in group_team should not own the group'
);

-- Test: Non-existent user should not own the group
select ok(
    not user_owns_group('00000000-0000-0000-0000-000000000099'::uuid, :'group1ID'),
    'Non-existent user should not own the group'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;