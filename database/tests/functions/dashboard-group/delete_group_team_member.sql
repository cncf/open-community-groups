-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupID '00000000-0000-0000-0000-000000000021'
\set userID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, display_name, host, name, title, description, header_logo_url, theme)
values (:'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, community_id, email, name, username, email_verified)
values (:'userID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'userID', 'member', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: deleting an existing member should remove membership
select lives_ok(
    $$ select delete_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid) $$,
    'delete_group_team_member should succeed'
);
select results_eq(
    $$ select count(*) from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
    $$ values (0::bigint) $$,
    'Membership should be removed'
);

-- Test: deleting a non-existing member should raise error
select throws_ok(
    $$ select delete_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid) $$,
    'P0001',
    'user is not a group team member',
    'Second delete should fail since member no longer exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
