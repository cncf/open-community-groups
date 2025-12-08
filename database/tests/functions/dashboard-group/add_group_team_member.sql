-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000033'
\set user3ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (community_id, display_name, host, name, title, description, header_logo_url, theme) values
    (:'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb),
    (:'community2ID', 'C2', 'c2.example.com', 'c2', 'C2', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Category
insert into group_category (group_category_id, community_id, name) values
    (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, community_id, email, name, username, email_verified) values
    (:'user1ID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), :'communityID', 'carol@example.com', 'Carol', 'carol', true),
    (:'user3ID', gen_random_bytes(32), :'community2ID', 'bob@example.com', 'Bob', 'bob', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create pending membership for same community user
select lives_ok(
    $$ select add_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'organizer') $$,
    'Should succeed for same community user'
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

-- Should not fail for other community user (but not insert)
select lives_ok(
    $$ select add_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000032'::uuid, 'organizer') $$,
    'Should not fail for other community user'
);
select results_eq(
    $$ select count(*) from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000032'::uuid $$,
    $$ values (0::bigint) $$,
    'No membership should be created for other community user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
