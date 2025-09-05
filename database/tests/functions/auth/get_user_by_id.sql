-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set userWithTeamsID '00000000-0000-0000-0001-000000000001'
\set userNoTeamsID '00000000-0000-0000-0001-000000000002'
\set userGroupOnlyID '00000000-0000-0000-0001-000000000003'
\set userCommunityOnlyID '00000000-0000-0000-0001-000000000004'
\set userBothTeamsID '00000000-0000-0000-0001-000000000005'
\set nonExistentUserID '00000000-0000-0000-0001-999999999999'
\set groupID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'test.example.com',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Cloud Native Seattle Community'
);

-- User with all team memberships
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
    :'userWithTeamsID',
    'test@example.com',
    'testuser',
    true,
    'Test User',
    'test_hash',
    :'communityID',
    'hashed_password_here'
);

-- Group category
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'categoryID'::uuid,
    :'communityID',
    'Test Category'
);

-- Group
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
    :'categoryID'::uuid,
    :'communityID',
    :'categoryID'::uuid,
    'Kubernetes Study Group',
    'kubernetes-study',
    'Weekly Kubernetes study and discussion group',
    'https://example.com',
    'https://example.com/logo.png'
);

-- Group team membership
insert into group_team (
    group_id,
    user_id,
    role,
    accepted
) values (
    :'categoryID'::uuid,
    :'userWithTeamsID',
    'organizer',
    true
);

-- Community team membership
insert into community_team (
    accepted,
    community_id,
    user_id
) values (
    true,
    :'communityID',
    :'userWithTeamsID'
);

-- User without teams
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    :'userNoTeamsID',
    'nogroups@example.com',
    'nogroupsuser',
    true,
    'No Groups User',
    'test_hash_2',
    :'communityID'
);

-- User with group team only
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    :'userGroupOnlyID',
    'grouponly@example.com',
    'grouponlyuser',
    true,
    'Group Only User',
    'test_hash_3',
    :'communityID'
);

insert into group_team (
    group_id,
    user_id,
    role,
    accepted
) values (
    :'groupID'::uuid,
    :'userGroupOnlyID',
    'organizer',
    true
);

-- User with community team only
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    :'userCommunityOnlyID',
    'communityonly@example.com',
    'communityonlyuser',
    true,
    'Community Only User',
    'test_hash_4',
    :'communityID'
);

insert into community_team (
    accepted,
    community_id,
    user_id
) values (
    true,
    :'communityID',
    :'userCommunityOnlyID'
);

-- User with both teams
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    name,
    auth_hash,
    community_id
) values (
    :'userBothTeamsID',
    'both@example.com',
    'bothuser',
    true,
    'Both Teams User',
    'test_hash_5',
    :'communityID'
);

insert into group_team (
    group_id,
    user_id,
    role,
    accepted
) values (
    :'groupID'::uuid,
    :'userBothTeamsID',
    'organizer',
    true
);

insert into community_team (
    accepted,
    community_id,
    user_id
) values (
    true,
    :'communityID',
    :'userBothTeamsID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_user_by_id with include_password false should return user without password
select is(
    get_user_by_id(:'userWithTeamsID'::uuid, false)::jsonb,
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

-- Test: get_user_by_id with include_password true should return user with password
select is(
    get_user_by_id(:'userWithTeamsID'::uuid, true)::jsonb,
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

-- Test: get_user_by_id with non-existent ID should return null
select is(
    get_user_by_id(:'nonExistentUserID'::uuid, false)::jsonb,
    null::jsonb,
    'Should return null when ID does not exist'
);

-- Test: get_user_by_id with no team memberships should return false team flags
select is(
    get_user_by_id(:'userNoTeamsID'::uuid, false)::jsonb,
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

-- Test: get_user_by_id with group team only should return correct team flags
select is(
    get_user_by_id(:'userGroupOnlyID'::uuid, false)::jsonb,
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

-- Test: get_user_by_id with community team only should return correct team flags
select is(
    get_user_by_id(:'userCommunityOnlyID'::uuid, false)::jsonb,
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

-- Test: get_user_by_id with both team memberships should return both flags true
select is(
    get_user_by_id(:'userBothTeamsID'::uuid, false)::jsonb,
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
