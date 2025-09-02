-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set deletedGroupID '00000000-0000-0000-0000-000000000023'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    :'communityID',
    'test-community',
    'Test Community',
    'test.community.org',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Users
insert into "user" (user_id, username, email, community_id, auth_hash)
values 
    (:'user1ID', 'testuser1', 'user1@test.com', :'communityID', 'hash1'),
    (:'user2ID', 'testuser2', 'user2@test.com', :'communityID', 'hash2');

-- Groups (active, inactive, deleted)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values 
    (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false, false),
    (:'deletedGroupID', :'communityID', :'categoryID', 'Deleted Group', 'deleted-group', false, true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test successful join
select lives_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'User should be able to join an active group'
);

-- Verify user was added to group_member table
select ok(
    exists(select 1 from group_member where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid),
    'User should be added to group_member table after joining'
);

-- Test duplicate join attempt
select throws_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'P0001',
    'user is already a member of this group',
    'Should not allow user to join a group they are already a member of'
);

-- Test join inactive group
select throws_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'P0001',
    'group not found or inactive',
    'Should not allow user to join an inactive group'
);

-- Test join deleted group
select throws_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000023'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'P0001',
    'group not found or inactive',
    'Should not allow user to join a deleted group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;