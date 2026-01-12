-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set group2ID '00000000-0000-0000-0000-000000000022'
\set group3ID '00000000-0000-0000-0000-000000000023'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set userID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (community_id, name, display_name, description, logo_url, banner_url) values
    (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/banner.png'),
    (:'community2ID', 'c2', 'C2', 'd', 'https://e/logo.png', 'https://e/banner.png');

-- Categories
insert into group_category (group_category_id, community_id, name) values
    (:'category1ID', :'communityID', 'Tech'),
    (:'category2ID', :'community2ID', 'Tech2');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'group1ID', :'communityID', :'category1ID', 'G1', 'g1'),
    (:'group2ID', :'communityID', :'category1ID', 'G2', 'g2'),
    (:'group3ID', :'community2ID', :'category2ID', 'G3', 'g3');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true, 'Bob');

-- Pending group invitations (two in main community, one in other community)
insert into group_team (group_id, user_id, role, accepted, created_at) values
    (:'group1ID', :'userID', 'organizer', false, '2024-01-02 10:00:00+00'),
    (:'group2ID', :'userID', 'organizer', false, '2024-01-03 10:00:00+00'),
    (:'group3ID', :'userID', 'organizer', false, '2024-01-04 10:00:00+00');

-- Accepted membership should not be listed (mark existing invite as accepted)
update group_team
set accepted = true
where group_id = :'group2ID'
  and user_id = :'userID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list all pending invitations for a user across all communities
select is(
    list_user_group_team_invitations(:'userID'::uuid)::jsonb,
    '[
        {"community_name": "c2", "group_id": "00000000-0000-0000-0000-000000000023", "group_name": "G3", "role": "organizer", "created_at": 1704362400},
        {"community_name": "c1", "group_id": "00000000-0000-0000-0000-000000000021", "group_name": "G1", "role": "organizer", "created_at": 1704189600}
    ]'::jsonb,
    'Should list all pending invitations for the user ordered by created_at desc'
);

-- Should return empty list when no pending invites present for a user
select is(
    list_user_group_team_invitations(:'user2ID'::uuid)::text,
    '[]',
    'No invitations should result in empty list'
);

-- Should not return accepted invitations
update group_team
set accepted = true
where group_id = :'group3ID'
  and user_id = :'userID';
select is(
    list_user_group_team_invitations(:'userID'::uuid)::jsonb,
    '[
        {"community_name": "c1", "group_id": "00000000-0000-0000-0000-000000000021", "group_name": "G1", "role": "organizer", "created_at": 1704189600}
    ]'::jsonb,
    'Should not return accepted invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
