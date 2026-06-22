-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '6a050000-0000-0000-0000-000000000001'
\set deletedGroupID '6a050000-0000-0000-0000-000000000002'
\set groupCategoryID '6a050000-0000-0000-0000-000000000003'
\set groupID '6a050000-0000-0000-0000-000000000004'
\set inactiveGroupID '6a050000-0000-0000-0000-000000000005'
\set user1ID '6a050000-0000-0000-0000-000000000006'
\set user2ID '6a050000-0000-0000-0000-000000000007'

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

-- Groups
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values
    (:'groupID', :'allianceID', :'groupCategoryID', 'Active Group', 'active-group', true, false),
    (
        :'inactiveGroupID',
        :'allianceID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false,
        false
    ),
    (
        :'deletedGroupID',
        :'allianceID',
        :'groupCategoryID',
        'Deleted Group',
        'deleted-group',
        false,
        true
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed for active group
select lives_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID', :'groupID', :'user1ID'
    ),
    'User should be able to join an active group'
);

-- Should add user to group_member table
select ok(
    exists(select 1 from group_member where group_id = :'groupID'::uuid and user_id = :'user1ID'::uuid),
    'User should be added to group_member table after joining'
);

-- Should error on duplicate join
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID', :'groupID', :'user1ID'
    ),
    'user is already a member of this group',
    'Should not allow user to join a group they are already a member of'
);

-- Should error for inactive group
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID', :'inactiveGroupID', :'user1ID'
    ),
    'group not found or inactive',
    'Should not allow user to join an inactive group'
);

-- Should error for deleted group
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID', :'deletedGroupID', :'user1ID'
    ),
    'group not found or inactive',
    'Should not allow user to join a deleted group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
