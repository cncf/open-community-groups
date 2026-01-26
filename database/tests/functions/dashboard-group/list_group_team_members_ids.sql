-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'

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
insert into "user" (user_id, auth_hash, email, name, username, email_verified, photo_url)
values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true, 'https://example.com/alice.png'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', false, 'https://example.com/bob.png'),
    (:'user3ID', gen_random_bytes(32), 'cora@example.com', 'Cora', 'cora', true, 'https://example.com/cora.png');

-- Group team
insert into group_team (group_id, user_id, accepted, role)
values
    (:'groupID', :'user1ID', true, 'organizer'),
    (:'groupID', :'user2ID', true, 'organizer'),
    (:'groupID', :'user3ID', false, 'organizer');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return accepted, verified team member user ids ordered by user id
select is(
    list_group_team_members_ids(:'groupID'::uuid)::jsonb,
    json_build_array(:'user1ID'::uuid)::jsonb,
    'Should return accepted, verified team member user ids ordered by user id'
);

-- Should return empty list for non-existing group
select is(
    list_group_team_members_ids('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
