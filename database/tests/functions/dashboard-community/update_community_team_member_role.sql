-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified)
values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true);

-- Community team membership
insert into community_team (community_id, user_id, role, accepted)
values
    (:'communityID', :'user1ID', 'viewer', true),
    (:'communityID', :'user2ID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    $$ select update_community_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'admin') $$,
    'Should succeed'
);
select results_eq(
    $$ select role from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
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
            community_id,
            resource_type,
            resource_id,
            details
        from audit_log
    $$,
    $$
        values (
            'community_team_member_role_updated',
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
    $$ select update_community_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000099'::uuid, 'admin') $$,
    'user is not a community team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    $$ select update_community_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'invalid') $$,
    '23503',
    'insert or update on table "community_team" violates foreign key constraint "community_team_role_fkey"',
    'Should error when updating role to an invalid value'
);

-- Should allow demoting an admin when another accepted admin remains
select lives_ok(
    $$ select update_community_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'viewer') $$,
    'Should allow demotion when another accepted admin exists'
);

-- Should block demoting the last accepted community admin
select throws_ok(
    $$ select update_community_team_member_role(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000032'::uuid, 'viewer') $$,
    'cannot change role for the last accepted community admin',
    'Should block demoting the last accepted community admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
