-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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
values (:'groupID', :'userID', 'organizer', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: updating existing member role should change it
select lives_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'organizer') $$,
    'update_group_team_member_role should succeed'
);
select results_eq(
    $$ select role from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
    $$ values ('organizer'::text) $$,
    'Role should be updated to organizer'
);

-- Test: updating non-existing membership should raise error
select throws_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000099'::uuid, 'organizer') $$,
    'P0001',
    'user is not a group team member',
    'Should error when updating role for non-existing member'
);

-- Test: updating to an invalid role should raise foreign key violation
select throws_ok(
    $$ select update_group_team_member_role('00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid, 'invalid') $$,
    '23503',
    'insert or update on table "group_team" violates foreign key constraint "group_team_role_fkey"',
    'Should error when updating role to an invalid value'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
