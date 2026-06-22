-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID '6a040000-0000-0000-0000-000000000001'
\set allianceID '6a040000-0000-0000-0000-000000000002'
\set groupCategoryID '6a040000-0000-0000-0000-000000000003'
\set inactiveGroupID '6a040000-0000-0000-0000-000000000004'
\set unknownGroupID '6a040000-0000-0000-0000-000000000005'
\set user1ID '6a040000-0000-0000-0000-000000000006'
\set user2ID '6a040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'hash1', 'user1@test.com', true, 'testuser1'),
    (:'user2ID', 'hash2', 'user2@test.com', true, 'testuser2');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active
) values
    (:'activeGroupID', :'allianceID', :'groupCategoryID', 'Active Group', 'active-group', true),
    (
        :'inactiveGroupID',
        :'allianceID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false
    );

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
    is_group_member(:'allianceID'::uuid, :'activeGroupID'::uuid, :'user1ID'::uuid),
    'Should return true for existing group member'
);

-- Should return false for non-member
select ok(
    not is_group_member(:'allianceID'::uuid, :'activeGroupID'::uuid, :'user2ID'::uuid),
    'Should return false for non-member'
);

-- Should return false for invalid group
select ok(
    not is_group_member(:'allianceID'::uuid, :'unknownGroupID'::uuid, :'user1ID'::uuid),
    'Should return false for invalid group'
);

-- Should return false for inactive group even if user is a member
select ok(
    not is_group_member(:'allianceID'::uuid, :'inactiveGroupID'::uuid, :'user1ID'::uuid),
    'Should return false for inactive group even if user is a member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
