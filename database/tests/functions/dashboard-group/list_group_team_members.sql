-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

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
values
    (:'user1ID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), :'communityID', 'bob@example.com', null, 'bob', true);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'organizer', true),
    (:'groupID', :'user2ID', 'member', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: list_group_team_members should include both members with acceptance state
select is(
    list_group_team_members(:'groupID'::uuid)::jsonb,
    '[
        {"accepted": true, "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "name": "Alice", "photo_url": null, "role": "organizer"},
        {"accepted": false, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "name": null, "photo_url": null, "role": "member"}
    ]'::jsonb,
    'Should return list of group team members with accepted flag'
);

-- Test: list_group_team_members for empty group should return empty array
select is(
    list_group_team_members('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
