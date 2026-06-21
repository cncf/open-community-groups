-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'alliance1ID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png'),
    (:'alliance2ID', 'c2', 'C2', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'user1ID', gen_random_bytes(32), 'u1@example.com', 'u1', true, 'U1'),
    (:'user2ID', gen_random_bytes(32), 'u2@example.com', 'u2', true, 'U2'),
    (:'user3ID', gen_random_bytes(32), 'u3@example.com', 'u3', true, 'U3');

-- Invitations
insert into alliance_team (
    accepted, alliance_id, created_at, role, user_id
) values
    (false, :'alliance1ID', '2024-01-02 03:04:05+00', 'admin', :'user1ID'),
    (false, :'alliance2ID', '2024-01-03 03:04:05+00', 'viewer', :'user1ID'),
    (false, :'alliance2ID', current_timestamp, 'viewer', :'user3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all pending invitations for a user across all alliances
select results_eq(
    $$ select list_user_alliance_team_invitations('00000000-0000-0000-0000-000000000011'::uuid)::jsonb $$,
    $$ values ('[
        {"alliance_id":"00000000-0000-0000-0000-000000000002","alliance_name":"c2","role":"viewer","created_at":1704251045},
        {"alliance_id":"00000000-0000-0000-0000-000000000001","alliance_name":"c1","role":"admin","created_at":1704164645}
    ]'::jsonb) $$,
    'Should return all pending invitations for the user ordered by created_at desc'
);

-- Should return empty array when user has no pending invitations
select results_eq(
    $$ select list_user_alliance_team_invitations('00000000-0000-0000-0000-000000000012'::uuid)::jsonb $$,
    $$ values ('[]'::jsonb) $$,
    'Should return empty array when there are no pending invitations'
);

-- Should not return accepted invitations
update alliance_team set accepted = true
where alliance_id = :'alliance1ID' and user_id = :'user1ID';
select results_eq(
    $$ select list_user_alliance_team_invitations('00000000-0000-0000-0000-000000000011'::uuid)::jsonb $$,
    $$ values ('[{"alliance_id":"00000000-0000-0000-0000-000000000002","alliance_name":"c2","role":"viewer","created_at":1704251045}]'::jsonb) $$,
    'Should not return accepted invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
