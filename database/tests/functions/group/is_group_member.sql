-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '00000000-0000-0000-0000-000000000021'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set allianceID '00000000-0000-0000-0000-000000000001'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'test-alliance', 'Test Alliance', 'A test alliance', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'categoryID', 'Technology', :'allianceID');

-- User
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'hash1', 'user1@test.com', 'testuser1'),
    (:'user2ID', 'hash2', 'user2@test.com', 'testuser2');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active
) values
    (:'activeGroupID', :'allianceID', :'categoryID', 'Active Group', 'active-group', true),
    (:'inactiveGroupID', :'allianceID', :'categoryID', 'Inactive Group', 'inactive-group', false);

-- Group Member (active group)
insert into group_member (group_id, user_id)
values (:'activeGroupID', :'user1ID');

-- Group Member (inactive group)
insert into group_member (group_id, user_id)
values (:'inactiveGroupID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return true for existing group member
select ok(
    is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid),
    'Should return true for existing group member'
);

-- Should return false for non-member
select ok(
    not is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000032'::uuid),
    'Should return false for non-member'
);

-- Should return false for invalid group
select ok(
    not is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000031'::uuid),
    'Should return false for invalid group'
);

-- Should return false for inactive group even if user is a member
select ok(
    not is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid, '00000000-0000-0000-0000-000000000031'::uuid),
    'Should return false for inactive group even if user is a member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
