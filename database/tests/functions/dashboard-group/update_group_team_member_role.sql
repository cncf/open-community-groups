-- Tests updating a group team member role.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a3f0000-0000-0000-0000-000000000008'
\set communityID '3a3f0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a3f0000-0000-0000-0000-000000000002'
\set groupID '3a3f0000-0000-0000-0000-000000000003'
\set lastAdminGroupID '3a3f0000-0000-0000-0000-000000000009'
\set missingUserID '3a3f0000-0000-0000-0000-000000000004'
\set user1ID '3a3f0000-0000-0000-0000-000000000006'
\set user2ID '3a3f0000-0000-0000-0000-000000000007'
\set viewerUserID '3a3f0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'actorUserID', jsonb_build_object('username', 'actor-update-group-team-member-role'));
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'viewerUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'lastAdminGroupID', :'communityID', :'groupCategoryID');

-- Group team with two accepted admins and an accepted viewer
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'admin', true),
    (:'groupID', :'user2ID', 'admin', true),
    (:'groupID', :'viewerUserID', 'viewer', true);

-- Group team with a single accepted admin
insert into group_team (group_id, user_id, role, accepted)
values (:'lastAdminGroupID', :'user1ID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    format(
        $$select update_group_team_member_role(%L::uuid, %L::uuid, %L::uuid, 'events-manager')$$,
        :'actorUserID', :'groupID', :'viewerUserID'
    ),
    'Should change existing member role'
);
select results_eq(
    format(
        $$select role from group_team where group_id = %L::uuid and user_id = %L::uuid$$,
        :'groupID', :'viewerUserID'
    ),
    $$ values ('events-manager'::text) $$,
    'Should update the member role to events-manager'
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
                resource_id,
                details
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'viewerUserID'
    ),
    format(
        $$
        values (
            'group_team_member_role_updated',
            %L::uuid,
            'actor-update-group-team-member-role'::text,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid,
            jsonb_build_object('role', 'events-manager')
        )
        $$,
        :'actorUserID', :'communityID', :'groupID', :'viewerUserID'
    ),
    'Should create the expected audit row'
);

-- Should error when updating role for non-existing member
select throws_ok(
    format(
        $$select update_group_team_member_role(%L::uuid, %L::uuid, %L::uuid, 'admin')$$,
        :'actorUserID', :'groupID', :'missingUserID'
    ),
    'OCG01',
    'user is not a group team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    format(
        $$select update_group_team_member_role(%L::uuid, %L::uuid, %L::uuid, 'invalid')$$,
        :'actorUserID', :'groupID', :'user1ID'
    ),
    '23503',
    null,
    'Should error when updating role to an invalid value'
);

-- Should allow demotion when another accepted admin exists
select lives_ok(
    format(
        $$select update_group_team_member_role(%L::uuid, %L::uuid, %L::uuid, 'viewer')$$,
        :'actorUserID', :'groupID', :'user1ID'
    ),
    'Should allow demotion when another accepted admin exists'
);
select results_eq(
    format(
        $$select role from group_team where group_id = %L::uuid and user_id = %L::uuid$$,
        :'groupID', :'user1ID'
    ),
    $$ values ('viewer'::text) $$,
    'Should update the demoted admin role to viewer'
);

-- Should block demoting the last accepted group admin
select throws_ok(
    format(
        $$select update_group_team_member_role(%L::uuid, %L::uuid, %L::uuid, 'viewer')$$,
        :'actorUserID', :'lastAdminGroupID', :'user1ID'
    ),
    'OCG01',
    'cannot change role for the last accepted group admin',
    'Should block demoting the last accepted group admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
