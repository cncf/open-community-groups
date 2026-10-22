-- Tests updating dashboard community team member roles.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c150000-0000-0000-0000-000000000001'
\set blockedAdminID '2c150000-0000-0000-0000-000000000002'
\set blockedCommunityID '2c150000-0000-0000-0000-000000000003'
\set blockedPendingAdminID '2c150000-0000-0000-0000-000000000004'
\set demoteAdminID '2c150000-0000-0000-0000-000000000005'
\set demoteCommunityID '2c150000-0000-0000-0000-000000000006'
\set demoteRemainingAdminID '2c150000-0000-0000-0000-000000000007'
\set promoteCommunityID '2c150000-0000-0000-0000-000000000008'
\set promoteViewerID '2c150000-0000-0000-0000-000000000009'
\set unknownUserID '2c150000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities for the blocked, demote and promote scenarios
select fx_community(:'blockedCommunityID');
select fx_community(:'demoteCommunityID');
select fx_community(:'promoteCommunityID');

-- Team member users
select fx_user(:'blockedAdminID');
select fx_user(:'blockedPendingAdminID');
select fx_user(:'demoteAdminID');
select fx_user(:'demoteRemainingAdminID');
select fx_user(:'promoteViewerID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-community-team-member-role-audit-actor'));

-- Blocked demotion: one accepted admin and one pending admin that does not count
insert into community_team (community_id, user_id, role, accepted)
values
    (:'blockedCommunityID', :'blockedAdminID', 'admin', true),
    (:'blockedCommunityID', :'blockedPendingAdminID', 'admin', false);

-- Allowed demotion: two accepted admins
insert into community_team (community_id, user_id, role, accepted)
values
    (:'demoteCommunityID', :'demoteAdminID', 'admin', true),
    (:'demoteCommunityID', :'demoteRemainingAdminID', 'admin', true);

-- Promotion: one accepted viewer
insert into community_team (community_id, user_id, role, accepted)
values (:'promoteCommunityID', :'promoteViewerID', 'viewer', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    format(
        $$ select update_community_team_member_role(%L::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'actorUserID',
        :'promoteCommunityID',
        :'promoteViewerID'
    ),
    'Should update member role to admin'
);
select results_eq(
    format(
        $$ select role from community_team where community_id = %L::uuid and user_id = %L::uuid $$,
        :'promoteCommunityID',
        :'promoteViewerID'
    ),
    $$ values ('admin'::text) $$,
    'Role should be updated to admin'
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
                resource_id,
                details
            from audit_log
            where community_id = %L::uuid
        $$,
        :'promoteCommunityID'
    ),
    format(
        $$
        values (
            'community_team_member_role_updated',
            %L::uuid,
            'update-community-team-member-role-audit-actor',
            %L::uuid,
            'user',
            %L::uuid,
            jsonb_build_object('role', 'admin')
        )
        $$,
        :'actorUserID',
        :'promoteCommunityID',
        :'promoteViewerID'
    ),
    'Should create the expected audit row'
);

-- Should error when updating role for non-existing member
select throws_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'promoteCommunityID',
        :'unknownUserID'
    ),
    'OCG01',
    'user is not a community team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'invalid') $$,
        :'promoteCommunityID',
        :'promoteViewerID'
    ),
    '23503',
    null,
    'Should error when updating role to an invalid value'
);

-- Should allow demoting an admin when another accepted admin remains
select lives_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer') $$,
        :'demoteCommunityID',
        :'demoteAdminID'
    ),
    'Should allow demotion when another accepted admin exists'
);
select results_eq(
    format(
        $$ select role from community_team where community_id = %L::uuid and user_id = %L::uuid $$,
        :'demoteCommunityID',
        :'demoteAdminID'
    ),
    $$ values ('viewer'::text) $$,
    'Role should be updated to viewer'
);

-- Should block demoting the last accepted community admin
select throws_ok(
    format(
        $$ select update_community_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer') $$,
        :'blockedCommunityID',
        :'blockedAdminID'
    ),
    'OCG01',
    'cannot change role for the last accepted community admin',
    'Should block demoting the last accepted community admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
