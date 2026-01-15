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
\set user2ID '00000000-0000-0000-0000-000000000012'

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

-- Users
insert into "user" (
    user_id, auth_hash, email, name, username, email_verified
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Adding a user should create membership
select lives_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'Should succeed for valid user'
);
select results_eq(
    $$
    select
        count(*)::bigint,
        bool_or(accepted)
    from community_team
    where community_id = '00000000-0000-0000-0000-000000000001'::uuid
      and user_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
    $$ values (1::bigint, false) $$,
    'Membership should be created with accepted = false'
);

-- Should not allow duplicate community team membership
select throws_ok(
    $$ select add_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'user is already a community team member',
    'Should not allow duplicate community team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
