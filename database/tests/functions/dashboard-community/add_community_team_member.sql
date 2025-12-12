-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id, display_name, host, name, title, description, header_logo_url, theme
) values
    (:'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb),
    (:'community2ID', 'C2', 'c2.example.com', 'c2', 'C2', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Users
insert into "user" (
    user_id, auth_hash, community_id, email, name, username, email_verified
) values
    (:'user1ID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), :'community2ID', 'bob@example.com', 'Bob', 'bob', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Adding a user from the same community should create membership
select lives_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'Should succeed for same community user'
);
select results_eq(
    $$
    select
        count(*)::bigint,
        bool_or(accepted)
    from community_team
    where community_id = '00000000-0000-0000-0000-000000000001'::uuid
      and user_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
    $$ values (1::bigint, false) $$,
    'Membership should be created with accepted = false'
);

-- Should not allow duplicate community team membership
select throws_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'user is already a community team member',
    'Should not allow duplicate community team membership'
);

-- Should fail for user from another community
select throws_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000012'::uuid) $$,
    'user not found in community',
    'Should fail for other community user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
