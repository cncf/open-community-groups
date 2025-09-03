-- =============================================================================
-- SETUP
-- =============================================================================

begin;
select plan(3);

-- =============================================================================
-- VARIABLES
-- =============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Community
insert into community (
    community_id, display_name, host, name, title, description, header_logo_url, theme
) values (
    :'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb
);

-- User
insert into "user" (
    user_id, auth_hash, community_id, email, name, username, email_verified
) values (
    :'user1ID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true
);

insert into community_team (community_id, user_id) values (:'communityID', :'user1ID');

-- =============================================================================
-- TESTS
-- =============================================================================

-- Test: removing membership deletes the row
select lives_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'delete_community_team_member should succeed'
);
select results_eq(
    $$ select count(*) from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000011'::uuid $$,
    $$ values (0::bigint) $$,
    'Membership row should be removed'
);

-- Test: removing a non-member should error
select throws_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'P0001',
    'user is not a community team member',
    'Should not allow deleting when membership does not exist'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

select * from finish();
rollback;
