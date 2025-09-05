-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set group2ID '00000000-0000-0000-0000-000000000022'
\set groupOtherID '00000000-0000-0000-0000-000000000023'
\set userID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (community_id, display_name, host, name, title, description, header_logo_url, theme) values
    (:'communityID', 'C1', 'c1.example.com', 'c1', 'C1', 'd', 'https://e/logo.png', '{}'::jsonb),
    (:'otherCommunityID', 'C2', 'c2.example.com', 'c2', 'C2', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Categories
insert into group_category (group_category_id, community_id, name) values
    (:'category1ID', :'communityID', 'Tech'),
    (:'category2ID', :'otherCommunityID', 'Tech2');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'group1ID', :'communityID', :'category1ID', 'G1', 'g1'),
    (:'group2ID', :'communityID', :'category1ID', 'G2', 'g2'),
    (:'groupOtherID', :'otherCommunityID', :'category2ID', 'G3', 'g3');

-- User
insert into "user" (user_id, auth_hash, community_id, email, name, username, email_verified) values
    (:'userID', gen_random_bytes(32), :'communityID', 'alice@example.com', 'Alice', 'alice', true);

-- Pending group invitations (two in main community, one in other community)
insert into group_team (group_id, user_id, role, accepted, created_at) values
    (:'group1ID', :'userID', 'organizer', false, '2024-01-02 10:00:00+00'),
    (:'group2ID', :'userID', 'organizer', false, '2024-01-03 10:00:00+00'),
    (:'groupOtherID', :'userID', 'organizer', false, '2024-01-04 10:00:00+00');

-- Accepted membership should not be listed (mark existing invite as accepted)
update group_team
set accepted = true
where group_id = :'group2ID'
  and user_id = :'userID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: should list only pending invitations for current community ordered by created_at desc
select is(
    list_user_group_team_invitations(:'communityID'::uuid, :'userID'::uuid)::jsonb,
    '[
        {"group_id": "00000000-0000-0000-0000-000000000021", "group_name": "G1", "role": "organizer", "created_at": 1704189600}
    ]'::jsonb,
    'Should list only pending invitations for current community ordered by creation time'
);

-- Test: for other community should return empty list
select is(
    list_user_group_team_invitations(:'otherCommunityID'::uuid, :'userID'::uuid)::text,
    '[]',
    'Other community should not include main community invites'
);

-- Test: when no invites present should return empty list
delete from group_team where user_id = :'userID';
select is(
    list_user_group_team_invitations(:'communityID'::uuid, :'userID'::uuid)::text,
    '[]',
    'No invitations should result in empty list'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
