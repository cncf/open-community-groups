-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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
insert into "user" (user_id, auth_hash, email, email_verified, name, username)
values (:'userID', gen_random_bytes(32), 'user@example.com', true, 'User', 'user');

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

-- Should remove the pending invitation
select lives_ok(
    $$ select reject_alliance_team_invitation('00000000-0000-0000-0000-000000000011'::uuid, '00000000-0000-0000-0000-000000000001'::uuid) $$,
    'Should remove the pending invitation'
);

-- Should delete the pending invitation row
select is(
    (
        select count(*)::int
        from alliance_team
        where alliance_id = :'allianceID'::uuid
        and user_id = :'userID'::uuid
    ),
    0,
    'Should delete the pending invitation row'
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
            'alliance_team_invitation_rejected',
            '00000000-0000-0000-0000-000000000011'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000001'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000011'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should reject a second rejection when no pending invitation exists
select throws_ok(
    $$ select reject_alliance_team_invitation('00000000-0000-0000-0000-000000000011'::uuid, '00000000-0000-0000-0000-000000000001'::uuid) $$,
    'no pending alliance invitation found',
    'Should reject a second rejection when no pending invitation exists'
);

-- Should not create an audit row when the rejection fails
select is(
    (select count(*)::int from audit_log),
    1,
    'Should not create an audit row when the rejection fails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
