-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a100000-0000-0000-0000-000000000001'
\set userID '4a100000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'Seattle community for cloud native technologies',
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
);

-- Pending invitation
insert into community_team (
    accepted,
    community_id,
    role,
    user_id
) values (
    false,
    :'communityID',
    'viewer',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove the pending invitation
select lives_ok(
    format(
        $$
            select reject_community_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'communityID'
    ),
    'Should remove the pending invitation'
);

-- Should delete the pending invitation row
select is(
    (
        select count(*)::int
        from community_team
        where community_id = :'communityID'::uuid
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
            community_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
            values (
                'community_team_invitation_rejected',
                %L::uuid,
                'user',
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'userID',
        :'communityID',
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should reject a second rejection when no pending invitation exists
select throws_ok(
    format(
        $$
            select reject_community_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'communityID'
    ),
    'no pending community invitation found',
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
