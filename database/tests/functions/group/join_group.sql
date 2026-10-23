-- Tests joining an active group of a community as a member.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a050000-0000-0000-0000-000000000001'
\set groupCategoryID '6a050000-0000-0000-0000-000000000003'
\set groupID '6a050000-0000-0000-0000-000000000004'
\set inactiveGroupID '6a050000-0000-0000-0000-000000000005'
\set otherCommunityGroupCategoryID '6a050000-0000-0000-0000-000000000009'
\set otherCommunityGroupID '6a050000-0000-0000-0000-000000000010'
\set otherCommunityID '6a050000-0000-0000-0000-000000000008'
\set userID '6a050000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, category, user and active group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Inactive group rejected by membership mutations
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Active group of another community rejected by membership mutations
select fx_community(:'otherCommunityID');
select fx_group_category(:'otherCommunityGroupCategoryID', :'otherCommunityID');
select fx_group(:'otherCommunityGroupID', :'otherCommunityID', :'otherCommunityGroupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed for active group
select lives_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'groupID', :'userID'
    ),
    'User should be able to join an active group'
);

-- Should add user to group_member table
select ok(
    exists(select 1 from group_member where group_id = :'groupID'::uuid and user_id = :'userID'::uuid),
    'User should be added to group_member table after joining'
);

-- Should error on duplicate join
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'groupID', :'userID'
    ),
    'OCG01',
    'user is already a member of this group',
    'Should not allow user to join a group they are already a member of'
);

-- Should error for inactive group
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'inactiveGroupID', :'userID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should not allow user to join an inactive group'
);

-- Should error for group of another community
select throws_ok(
    format(
        $$select join_group(%L::uuid, %L::uuid, %L::uuid)$$,
        :'communityID', :'otherCommunityGroupID', :'userID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should not allow user to join a group of another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
