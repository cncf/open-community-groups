-- Tests deleting dashboard community team members.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c080000-0000-0000-0000-000000000001'
\set allowedAdminID '2c080000-0000-0000-0000-000000000002'
\set allowedCommunityID '2c080000-0000-0000-0000-000000000003'
\set allowedRemainingAdminID '2c080000-0000-0000-0000-000000000004'
\set blockedAdminID '2c080000-0000-0000-0000-000000000005'
\set blockedCommunityID '2c080000-0000-0000-0000-000000000006'
\set blockedPendingAdminID '2c080000-0000-0000-0000-000000000007'
\set nonMemberUserID '2c080000-0000-0000-0000-000000000008'
\set pendingAdminID '2c080000-0000-0000-0000-000000000009'
\set pendingCommunityID '2c080000-0000-0000-0000-00000000000a'
\set pendingRemainingAdminID '2c080000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities for the allowed, blocked and pending scenarios
select fx_community(:'allowedCommunityID');
select fx_community(:'blockedCommunityID');
select fx_community(:'pendingCommunityID');

-- Team member users
select fx_user(:'allowedAdminID');
select fx_user(:'allowedRemainingAdminID');
select fx_user(:'blockedAdminID');
select fx_user(:'blockedPendingAdminID');
select fx_user(:'pendingAdminID');
select fx_user(:'pendingRemainingAdminID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'delete-community-team-member-audit-actor'));

-- Allowed delete: two accepted admins
insert into community_team (community_id, user_id, accepted, role) values
    (:'allowedCommunityID', :'allowedAdminID', true, 'admin'),
    (:'allowedCommunityID', :'allowedRemainingAdminID', true, 'admin');

-- Blocked delete: one accepted admin and one pending admin that does not count
insert into community_team (community_id, user_id, accepted, role) values
    (:'blockedCommunityID', :'blockedAdminID', true, 'admin'),
    (:'blockedCommunityID', :'blockedPendingAdminID', false, 'admin');

-- Pending delete: one pending admin and one accepted admin
insert into community_team (community_id, user_id, accepted, role) values
    (:'pendingCommunityID', :'pendingAdminID', false, 'admin'),
    (:'pendingCommunityID', :'pendingRemainingAdminID', true, 'admin');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting an accepted admin when another accepted admin remains
select lives_ok(
    format(
        $$ select delete_community_team_member(%L::uuid, %L::uuid, %L::uuid) $$,
        :'actorUserID',
        :'allowedCommunityID',
        :'allowedAdminID'
    ),
    'Should allow deleting an accepted admin when another accepted admin remains'
);
select results_eq(
    format(
        $$ select count(*) from community_team where community_id = %L::uuid and user_id = %L::uuid $$,
        :'allowedCommunityID',
        :'allowedAdminID'
    ),
    $$ values (0::bigint) $$,
    'Deleted accepted membership row should be removed'
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
                resource_type,
                resource_id
            from audit_log
            where community_id = %L::uuid
        $$,
        :'allowedCommunityID'
    ),
    format(
        $$
        values (
            'community_team_member_removed',
            %L::uuid,
            'delete-community-team-member-audit-actor',
            %L::uuid,
            'user',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'allowedCommunityID',
        :'allowedAdminID'
    ),
    'Should create the expected audit row'
);

-- Should allow deleting a pending admin invitation when one accepted admin remains
select lives_ok(
    format(
        $$ select delete_community_team_member(%L::uuid, %L::uuid, %L::uuid) $$,
        :'actorUserID',
        :'pendingCommunityID',
        :'pendingAdminID'
    ),
    'Should allow deleting a pending admin invitation when one accepted admin remains'
);
select results_eq(
    format(
        $$ select count(*) from community_team where community_id = %L::uuid and user_id = %L::uuid $$,
        :'pendingCommunityID',
        :'pendingAdminID'
    ),
    $$ values (0::bigint) $$,
    'Deleted pending invitation row should be removed'
);

-- Should block deleting the last accepted community admin
select throws_ok(
    format(
        $$ select delete_community_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'blockedCommunityID',
        :'blockedAdminID'
    ),
    'OCG01',
    'cannot remove the last accepted community admin',
    'Should block deleting the last accepted community admin'
);

-- Should not allow deleting when membership does not exist
select throws_ok(
    format(
        $$ select delete_community_team_member(null::uuid, %L::uuid, %L::uuid) $$,
        :'blockedCommunityID',
        :'nonMemberUserID'
    ),
    'OCG01',
    'user is not a community team member',
    'Should not allow deleting when membership does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
