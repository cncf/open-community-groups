-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set userID '00000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url)
values (:'communityID', 'cloud-native-seattle', 'Cloud Native Seattle', 'Seattle community for cloud native technologies', 'https://example.com/logo.png');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name)
values (:'userID', gen_random_bytes(32), 'user@example.com', 'user', true, 'User');

-- Pending invitation
insert into community_team (
    accepted,
    community_id,
    user_id
) values (
    false,
    :'communityID',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flip accepted to true when accepting invitation
select lives_ok(
    $$ select accept_community_team_invitation('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'Should execute successfully'
);
select results_eq(
    $$ select accepted from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000011'::uuid $$,
    $$ values (true) $$,
    'Invitation should be marked as accepted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
