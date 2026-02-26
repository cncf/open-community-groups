-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, email, name, username, email_verified)
values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', true),
    (:'user3ID', gen_random_bytes(32), 'charlie@example.com', 'Charlie', 'charlie', true);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'organizer', true),
    (:'groupID', :'user2ID', 'organizer', true),
    (:'groupID', :'user3ID', 'organizer', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting an accepted member when another accepted member remains
select lives_ok(
    $$ select delete_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000032'::uuid) $$,
    'Should allow deleting an accepted member when another accepted member exists'
);
select results_eq(
    $$ select count(*) from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000032'::uuid $$,
    $$ values (0::bigint) $$,
    'Deleted accepted membership should be removed'
);

-- Should allow deleting a pending invitation when there is one accepted member left
select lives_ok(
    $$ select delete_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000033'::uuid) $$,
    'Should allow deleting a pending invitation with only one accepted member left'
);

-- Should block deleting the last accepted member
select throws_ok(
    $$ select delete_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid) $$,
    'cannot remove the last accepted group team member',
    'Should block deleting the last accepted member'
);
select results_eq(
    $$ select count(*) from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
    $$ values (1::bigint) $$,
    'Last accepted membership should remain after blocked delete'
);

-- Should raise error when deleting non-existing member
select throws_ok(
    $$ select delete_group_team_member('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000034'::uuid) $$,
    'user is not a group team member',
    'Should raise error when deleting non-existing member'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
