-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified)
values (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'alice', true);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'user1ID', 'admin', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should change existing member role
select lives_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'admin') $$,
    'Should succeed'
);
select results_eq(
    $$ select role from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
    $$ values ('admin'::text) $$,
    'Role should be updated to admin'
);

-- Should error when updating role for non-existing member
select throws_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000099'::uuid, 'admin') $$,
    'user is not a group team member',
    'Should error when updating role for non-existing member'
);

-- Should error when updating role to an invalid value
select throws_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'invalid') $$,
    '23503',
    'insert or update on table "group_team" violates foreign key constraint "group_team_role_fkey"',
    'Should error when updating role to an invalid value'
);

-- Should block demoting the last accepted group admin
select throws_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'viewer') $$,
    'cannot change role for the last accepted group admin',
    'Should block demoting the last accepted group admin'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
