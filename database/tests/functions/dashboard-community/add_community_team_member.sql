-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set userOtherID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id, display_name, host, name, title, description, header_logo_url, theme
) values
    (:'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb),
    (:'otherCommunityID', 'C2', 'c2.example.com', 'c2', 'C2', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Users
insert into "user" (
    user_id, auth_hash, community_id, email, name, username, email_verified
) values
    (:'user1ID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true),
    (:'userOtherID', gen_random_bytes(32), :'otherCommunityID', 'bob@example.com', 'Bob', 'bob', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: adding a user from the same community should create membership
select lives_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'add_community_team_member should succeed for same community user'
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

-- Test: adding an existing member should error
select throws_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'P0001',
    'user is already a community team member',
    'Should not allow duplicate community team membership'
);

-- Test: adding a user from another community should be ignored (not inserted)
select lives_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000012'::uuid) $$,
    'add_community_team_member should not fail for other community user'
);
select results_eq(
    $$ select count(*) from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000012'::uuid $$,
    $$ values (0::bigint) $$,
    'No membership should be created for other community user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
