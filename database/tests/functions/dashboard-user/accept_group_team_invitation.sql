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

insert into community (community_id, display_name, host, name, title, description, header_logo_url, theme)
values (:'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb);
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');
insert into "user" (user_id, auth_hash, community_id, email, name, username, email_verified)
values (:'userID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true);

-- Pending invite
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'userID', 'member', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: accepting a pending invite should flip accepted to true
select lives_ok(
    $$ select accept_group_team_invitation('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid) $$,
    'accept_group_team_invitation should succeed'
);
select results_eq(
    $$ select accepted from group_team where group_id = '00000000-0000-0000-0000-000000000021'::uuid and user_id = '00000000-0000-0000-0000-000000000031'::uuid $$,
    $$ values (true) $$,
    'Invite should be marked as accepted'
);

-- Test: accepting again should raise error when no pending invitation exists
select throws_ok(
    $$ select accept_group_team_invitation('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000021'::uuid, '00000000-0000-0000-0000-000000000031'::uuid) $$,
    'no pending group invitation found',
    'Second accept should fail since invite is no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
