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
insert into community (
    community_id,
    name,
    display_name,
    host,
    description,
    header_logo_url,
    theme,
    title
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'test.example.com',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Cloud Native Seattle Community'
);

-- User
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    :'userID',
    gen_random_bytes(32),
    :'communityID',
    'user@example.com',
    true,
    'User',
    'user'
);

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

-- Test: accepting a community team invitation should flip accepted to true
select lives_ok(
    $$ select accept_community_team_invitation('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'accept_community_team_invitation should execute successfully'
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
