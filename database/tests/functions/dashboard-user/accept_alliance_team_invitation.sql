-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'
\set userID '00000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'cloud-native-seattle', 'Cloud Native Seattle', 'Seattle alliance for cloud native technologies', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name)
values (:'userID', gen_random_bytes(32), 'user@example.com', 'user', true, 'User');

-- Pending invitation
insert into alliance_team (
    accepted,
    alliance_id,
    role,
    user_id
) values (
    false,
    :'allianceID',
    'viewer',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flip accepted to true when accepting invitation
select lives_ok(
    $$ select accept_alliance_team_invitation('00000000-0000-0000-0000-000000000011'::uuid, '00000000-0000-0000-0000-000000000001'::uuid) $$,
    'Should execute successfully'
);
select results_eq(
    $$ select accepted from alliance_team where alliance_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000011'::uuid $$,
    $$ values (true) $$,
    'Invitation should be marked as accepted'
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
            resource_id
        from audit_log
    $$,
    $$
        values (
            'alliance_team_invitation_accepted',
            '00000000-0000-0000-0000-000000000011'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000001'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000011'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
