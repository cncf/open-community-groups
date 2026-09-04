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

-- Baseline community, category, users and active group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Inactive group rejected by membership mutations
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Deleted group rejected by membership mutations
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));


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
    'OCG01',
    'user is not a member of this group',
    'Should not allow user to leave a group they are not a member of'
);

-- Should error for inactive group
select throws_ok(
    format(
        $$select leave_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'inactiveGroupID', :'user1ID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should not allow user to leave an inactive group'
);

-- Should error for deleted group
select throws_ok(
    format(
        $$select leave_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'deletedGroupID', :'user1ID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should not allow user to leave a deleted group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
