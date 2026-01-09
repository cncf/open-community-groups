-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set deletedGroupID '00000000-0000-0000-0000-000000000023'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'hash1', 'user1@test.com', 'testuser1'),
    (:'user2ID', 'hash2', 'user2@test.com', 'testuser2');

-- Groups
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

-- Should succeed for active group
select lives_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'User should be able to join an active group'
);

-- Should add user to group_member table
select ok(
    exists(select 1 from group_member where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid),
    'User should be added to group_member table after joining'
);

-- Should error on duplicate join
select throws_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'user is already a member of this group',
    'Should not allow user to join a group they are already a member of'
);

-- Should error for inactive group
select throws_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'group not found or inactive',
    'Should not allow user to join an inactive group'
);

-- Should error for deleted group
select throws_ok(
    $$select join_group('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000023'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'group not found or inactive',
    'Should not allow user to join a deleted group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
