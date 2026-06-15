-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a060000-0000-0000-0000-000000000001'
\set deletedGroupID '6a060000-0000-0000-0000-000000000002'
\set groupCategoryID '6a060000-0000-0000-0000-000000000003'
\set groupID '6a060000-0000-0000-0000-000000000004'
\set inactiveGroupID '6a060000-0000-0000-0000-000000000005'
\set user1ID '6a060000-0000-0000-0000-000000000006'
\set user2ID '6a060000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'hash1', 'user1@test.com', true, 'testuser1'),
    (:'user2ID', 'hash2', 'user2@test.com', true, 'testuser2');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values
    (:'groupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group', true, false),
    (
        :'inactiveGroupID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false,
        false
    ),
    (
        :'deletedGroupID',
        :'communityID',
        :'groupCategoryID',
        'Deleted Group',
        'deleted-group',
        false,
        true
    );

-- Group Member
insert into group_member (group_id, user_id)
values (:'groupID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed for member
select lives_ok(
    format(
        $$select leave_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'groupID', :'user1ID'
    ),
    'User should be able to leave a group they are a member of'
);

-- Should remove user from group_member table
select ok(
    not exists(select 1 from group_member where group_id = :'groupID'::uuid and user_id = :'user1ID'::uuid),
    'User should be removed from group_member table after leaving'
);

-- Should error when user is not a member
select throws_ok(
    format(
        $$select leave_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'groupID', :'user2ID'
    ),
    'user is not a member of this group',
    'Should not allow user to leave a group they are not a member of'
);

-- Should error for inactive group
select throws_ok(
    format(
        $$select leave_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'inactiveGroupID', :'user1ID'
    ),
    'group not found or inactive',
    'Should not allow user to leave an inactive group'
);

-- Should error for deleted group
select throws_ok(
    format(
        $$select leave_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'deletedGroupID', :'user1ID'
    ),
    'group not found or inactive',
    'Should not allow user to leave a deleted group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
