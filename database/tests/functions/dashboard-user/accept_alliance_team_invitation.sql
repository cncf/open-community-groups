-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '4a010000-0000-0000-0000-000000000001'
\set user2ID '4a010000-0000-0000-0000-000000000002'
\set userID '4a010000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'Seattle alliance for cloud native technologies',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'userID',
    gen_random_bytes(32),
    'user@example.com',
    true,
    'user',
    'User'
), (
    :'user2ID',
    gen_random_bytes(32),
    'user2@example.com',
    true,
    'user2',
    'User Two'
);

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
    format(
        $$
            select accept_alliance_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'allianceID'
    ),
    'Should accept a pending alliance team invitation'
);
select results_eq(
    format(
        $$
            select accepted
            from alliance_team
            where alliance_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'allianceID',
        :'userID'
    ),
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
    format(
        $$
            values (
                'alliance_team_invitation_accepted',
                %L::uuid,
                'user',
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'userID',
        :'allianceID',
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should reject accepting a non-existent invitation
select throws_ok(
    format(
        'select accept_alliance_team_invitation(%L::uuid, %L::uuid)',
        :'user2ID',
        :'allianceID'
    ),
    'no pending alliance invitation found',
    'Should reject accepting a non-existent invitation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
