-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set activeGroupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
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

-- Groups (active and inactive)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active
) values 
    (:'activeGroupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false);

-- Add user1 as a member of the active group
insert into group_member (group_id, user_id)
values (:'activeGroupID', :'user1ID');

-- Add user1 as a member of the inactive group (for testing)
insert into group_member (group_id, user_id)
values (:'inactiveGroupID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test existing member returns true
select ok(
    is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid),
    'Should return true for existing group member'
);

-- Test non-member returns false
select ok(
    not is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000032'::uuid),
    'Should return false for non-member'
);

-- Test invalid group returns false
select ok(
    not is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000031'::uuid),
    'Should return false for invalid group'
);

-- Test inactive group returns false (even if user is a member)
select ok(
    not is_group_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000022'::uuid, '00000000-0000-0000-0000-000000000031'::uuid),
    'Should return false for inactive group even if user is a member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;