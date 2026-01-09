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

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png');

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
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', null, 'bob', true, 'https://example.com/bob.png');

-- Group members
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'groupID', :'user2ID', '2024-01-02 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return members user ids ordered by user id
select is(
    list_group_members_ids(:'groupID'::uuid)::jsonb,
    json_build_array(:'user1ID'::uuid, :'user2ID'::uuid)::jsonb,
    'Should return members user ids ordered by user id'
);

-- Should return empty list for non-existing group
select is(
    list_group_members_ids('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
