-- Tests deleting group team members.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a0d0000-0000-0000-0000-000000000008'
\set communityID '3a0d0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a0d0000-0000-0000-0000-000000000002'
\set groupID '3a0d0000-0000-0000-0000-000000000003'
\set lastAdminGroupID '3a0d0000-0000-0000-0000-000000000009'
\set lastAdminPendingUserID '3a0d0000-0000-0000-0000-00000000000a'
\set lastAdminUserID '3a0d0000-0000-0000-0000-00000000000b'
\set user1ID '3a0d0000-0000-0000-0000-000000000004'
\set user2ID '3a0d0000-0000-0000-0000-000000000005'
\set user4ID '3a0d0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'actorID', jsonb_build_object('username', 'actor-delete-group-team-member'));
select fx_user(:'lastAdminPendingUserID');
select fx_user(:'lastAdminUserID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'lastAdminGroupID', :'communityID', :'groupCategoryID');

-- Group with two accepted admins
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'admin', true),
    (:'groupID', :'user2ID', 'admin', true);

-- Group with a single accepted admin and a pending admin invitation
insert into group_team (group_id, user_id, role, accepted)
values
    (:'lastAdminGroupID', :'lastAdminUserID', 'admin', true),
    (:'lastAdminGroupID', :'lastAdminPendingUserID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting an accepted member when another accepted member remains
select lives_ok(
    format(
        $$ select delete_group_team_member(%L::uuid, %L::uuid, %L::uuid) $$,
        :'actorID', :'groupID', :'user2ID'
    ),
    'Should allow deleting an accepted member when another accepted member exists'
);

-- Should remove the deleted accepted membership
select results_eq(
    format(
        $$
            select count(*)
            from group_team
            where group_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'groupID', :'user2ID'
    ),
    $$ values (0::bigint) $$,
    'Should remove the deleted accepted membership'
);

-- Should create the expected audit row
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                actor_username,
                community_id,
                group_id,
                resource_type,
                resource_id
            from audit_log
            where action = 'group_team_member_removed'
            and resource_id = %L::uuid
        $$,
        :'user2ID'
    ),
    format(
        $$
        values (
            'group_team_member_removed',
            %L::uuid,
            'actor-delete-group-team-member'::text,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid
        )
        $$,
        :'actorID', :'communityID', :'groupID', :'user2ID'
    ),
    'Should create the expected audit row'
);

-- Should block deleting the last accepted member
select throws_ok(
    format(
        $$ select delete_group_team_member(%L::uuid, %L::uuid, %L::uuid) $$,
        :'actorID', :'lastAdminGroupID', :'lastAdminUserID'
    ),
    'OCG01',
    'cannot remove the last accepted group admin',
    'Should block deleting the last accepted member'
);

-- Should allow deleting a pending invitation when there is one accepted member left
select lives_ok(
    format(
        $$ select delete_group_team_member(%L::uuid, %L::uuid, %L::uuid) $$,
        :'actorID', :'lastAdminGroupID', :'lastAdminPendingUserID'
    ),
    'Should allow deleting a pending invitation with only one accepted member left'
);

-- Should remove the deleted pending invitation
select results_eq(
    format(
        $$
            select count(*)
            from group_team
            where group_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'lastAdminGroupID', :'lastAdminPendingUserID'
    ),
    $$ values (0::bigint) $$,
    'Should remove the deleted pending invitation'
);

-- Should raise error when deleting non-existing member
select throws_ok(
    format(
        $$ select delete_group_team_member(%L::uuid, %L::uuid, %L::uuid) $$,
        :'actorID', :'groupID', :'user4ID'
    ),
    'OCG01',
    'user is not a group team member',
    'Should raise error when deleting non-existing member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
