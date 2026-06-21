-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified)
values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true);

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
    $$ select update_alliance_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'admin') $$,
    'Should succeed'
);
select results_eq(
    $$ select role from alliance_team where alliance_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
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
    $$
        values (
            'alliance_team_member_role_updated',
            null::uuid,
            null::text,
            '00000000-0000-0000-0000-000000000001'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000031'::uuid,
            jsonb_build_object('role', 'admin')
        )
    $$,
    'Should create the expected audit row'
);

-- Should error when updating role for non-existing member
select throws_ok(
    $$ select update_alliance_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000099'::uuid, 'admin') $$,
    'user is not a alliance team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    $$ select update_alliance_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'invalid') $$,
    '23503',
    'insert or update on table "alliance_team" violates foreign key constraint "alliance_team_role_fkey"',
    'Should error when updating role to an invalid value'
);

-- Should allow demoting an admin when another accepted admin remains
select lives_ok(
    $$ select update_alliance_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'viewer') $$,
    'Should allow demotion when another accepted admin exists'
);

-- Should block demoting the last accepted alliance admin
select throws_ok(
    $$ select update_alliance_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000032'::uuid, 'viewer') $$,
    'cannot change role for the last accepted alliance admin',
    'Should block demoting the last accepted alliance admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
