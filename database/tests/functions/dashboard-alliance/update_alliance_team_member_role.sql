-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c150000-0000-0000-0000-000000000001'
\set unknownUserID '2c150000-0000-0000-0000-000000000002'
\set user1ID '2c150000-0000-0000-0000-000000000003'
\set user2ID '2c150000-0000-0000-0000-000000000004'

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
    'team-member-role-alliance',
    'Team Member Role Alliance',
    'Alliance for team member role tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob');

-- Alliance team membership
insert into alliance_team (alliance_id, user_id, role, accepted)
values
    (:'allianceID', :'user1ID', 'viewer', true),
    (:'allianceID', :'user2ID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    format(
        $$ select update_alliance_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'allianceID',
        :'user1ID'
    ),
    'Should update member role to admin'
);
select results_eq(
    format(
        $$ select role from alliance_team where alliance_id = %L::uuid and user_id = %L::uuid $$,
        :'allianceID',
        :'user1ID'
    ),
    $$ values ('admin'::text) $$,
    'Role should be updated to admin'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            resource_type,
            resource_id,
            details
        from audit_log
    $$,
    format(
        $$
        values (
            'alliance_team_member_role_updated',
            null::uuid,
            null::text,
            %L::uuid,
            'user',
            %L::uuid,
            jsonb_build_object('role', 'admin')
        )
        $$,
        :'allianceID',
        :'user1ID'
    ),
    'Should create the expected audit row'
);

-- Should error when updating role for non-existing member
select throws_ok(
    format(
        $$ select update_alliance_team_member_role(null::uuid, %L::uuid, %L::uuid, 'admin') $$,
        :'allianceID',
        :'unknownUserID'
    ),
    'user is not a alliance team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    format(
        $$ select update_alliance_team_member_role(null::uuid, %L::uuid, %L::uuid, 'invalid') $$,
        :'allianceID',
        :'user1ID'
    ),
    '23503',
    null,
    'Should error when updating role to an invalid value'
);

-- Should allow demoting an admin when another accepted admin remains
select lives_ok(
    format(
        $$ select update_alliance_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer') $$,
        :'allianceID',
        :'user1ID'
    ),
    'Should allow demotion when another accepted admin exists'
);

-- Should block demoting the last accepted alliance admin
select throws_ok(
    format(
        $$ select update_alliance_team_member_role(null::uuid, %L::uuid, %L::uuid, 'viewer') $$,
        :'allianceID',
        :'user2ID'
    ),
    'cannot change role for the last accepted alliance admin',
    'Should block demoting the last accepted alliance admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
