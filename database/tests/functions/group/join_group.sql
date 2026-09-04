-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a050000-0000-0000-0000-000000000001'
\set deletedGroupID '6a050000-0000-0000-0000-000000000002'
\set groupCategoryID '6a050000-0000-0000-0000-000000000003'
\set groupID '6a050000-0000-0000-0000-000000000004'
\set inactiveGroupID '6a050000-0000-0000-0000-000000000005'
\set user1ID '6a050000-0000-0000-0000-000000000006'
\set user2ID '6a050000-0000-0000-0000-000000000007'

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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed for active group
select lives_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'groupID', :'user1ID'
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
        :'communityID', :'groupID', :'user1ID'
    ),
    'OCG01',
    'user is already a member of this group',
    'Should not allow user to join a group they are already a member of'
);

-- Should error for inactive group
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'inactiveGroupID', :'user1ID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should not allow user to join an inactive group'
);

-- Should error for deleted group
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'deletedGroupID', :'user1ID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should not allow user to join a deleted group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
