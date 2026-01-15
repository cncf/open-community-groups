-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000033'

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

-- Category
insert into group_category (group_category_id, community_id, name) values
    (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, email, name, username, email_verified) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'carol@example.com', 'Carol', 'carol', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create pending membership
select lives_ok(
    $$ select add_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'organizer') $$,
    'Should succeed for valid user'
);
select results_eq(
    $$
    select count(*)::bigint, bool_or(accepted)
    from group_team
    where group_id = '00000000-0000-0000-0000-000000000021'::uuid
      and user_id = '00000000-0000-0000-0000-000000000031'::uuid
    $$,
    $$ values (1::bigint, false) $$,
    'Membership should be created with accepted = false'
);

-- Should not allow adding membership with invalid role
select throws_ok(
    $$ select add_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000033'::uuid, 'invalid') $$,
    '23503',
    'insert or update on table "group_team" violates foreign key constraint "group_team_role_fkey"',
    'Should not allow adding membership with invalid role'
);

-- Should not allow duplicate group team membership
select throws_ok(
    $$ select add_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'organizer') $$,
    'user is already a group team member',
    'Should not allow duplicate group team membership'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
