-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'c1',
    'C1',
    'Community 1',
    'https://e/logo.png',
    'https://e/banner_mobile.png',
    'https://e/banner.png'
);

-- User
insert into "user" (
    user_id, auth_hash, email, name, username, email_verified
) values (
    :'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true
);

insert into community_team (community_id, user_id) values (:'communityID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove membership successfully
select lives_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'Should succeed'
);
select results_eq(
    $$ select count(*) from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000011'::uuid $$,
    $$ values (0::bigint) $$,
    'Membership row should be removed'
);

-- Should not allow deleting when membership does not exist
select throws_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'user is not a community team member',
    'Should not allow deleting when membership does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
