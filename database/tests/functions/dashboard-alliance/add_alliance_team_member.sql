-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'c1', 'C1', 'Alliance 1', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Users
insert into "user" (
    user_id, auth_hash, email, name, username, email_verified
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Adding a user should create membership
select lives_ok(
    $$ select add_alliance_team_member(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid, 'admin') $$,
    'Should succeed for valid user'
);
select results_eq(
    $$
    select
        count(*)::bigint,
        bool_or(accepted)
    from alliance_team
    where alliance_id = '00000000-0000-0000-0000-000000000001'::uuid
      and user_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
    $$ values (1::bigint, false) $$,
    'Membership should be created with accepted = false'
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
            'alliance_team_member_added',
            null::uuid,
            null::text,
            '00000000-0000-0000-0000-000000000001'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000011'::uuid,
            jsonb_build_object('role', 'admin')
        )
    $$,
    'Should create the expected audit row'
);

-- Should not allow duplicate alliance team membership
select throws_ok(
    $$ select add_alliance_team_member(null::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid, 'admin') $$,
    'user is already a alliance team member',
    'Should not allow duplicate alliance team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
