-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id, name, display_name, host, description, header_logo_url, theme, title
) values
    (:'community1ID', 'c1', 'C1', 'c1.example.com', 'd', 'https://e/logo.png', '{}'::jsonb, 'C1'),
    (:'community2ID', 'c2', 'C2', 'c2.example.com', 'd', 'https://e/logo.png', '{}'::jsonb, 'C2');

-- Users
insert into "user" (
    user_id, auth_hash, community_id, email, email_verified, name, username
) values
    (:'user1ID', gen_random_bytes(32), :'community1ID', 'u1@example.com', true, 'U1', 'u1'),
    (:'user2ID', gen_random_bytes(32), :'community1ID', 'u2@example.com', true, 'U2', 'u2');

-- Invitations
insert into community_team (
    accepted, community_id, created_at, user_id
) values
    (false, :'community1ID', '2024-01-02 03:04:05+00', :'user1ID'),   -- should be returned
    (false, :'community2ID', current_timestamp, :'user1ID');          -- other community, ignored

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only pending invitations for the given community
select results_eq(
    $$ select list_user_community_team_invitations('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid)::jsonb $$,
    $$ values ('[{"community_id":"00000000-0000-0000-0000-000000000001","community_name":"c1","created_at":1704164645}]'::jsonb) $$,
    'Should return only pending invitations for the given community'
);

-- Should return empty array when user has no pending invitations
select results_eq(
    $$ select list_user_community_team_invitations('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000012'::uuid)::jsonb $$,
    $$ values ('[]'::jsonb) $$,
    'Should return empty array when there are no pending invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
