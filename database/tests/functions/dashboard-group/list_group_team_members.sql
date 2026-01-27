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
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (user_id, auth_hash, company, email, name, title, username, email_verified)
values
    (:'user1ID', gen_random_bytes(32), 'Cloud Corp', 'alice@example.com', 'Alice', 'Organizer', 'alice', true),
    (:'user2ID', gen_random_bytes(32), null, 'bob@example.com', null, null, 'bob', true);

-- Group team membership
insert into group_team (group_id, user_id, role, accepted)
values
    (:'groupID', :'user1ID', 'organizer', true),
    (:'groupID', :'user2ID', 'organizer', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return list of group team members with accepted flag
select is(
    list_group_team_members(:'groupID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'approved_total', 1,
        'members', '[
            {"accepted": true, "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": null, "role": "organizer", "title": "Organizer"},
            {"accepted": false, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "company": null, "name": null, "photo_url": null, "role": "organizer", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return list of group team members with accepted flag'
);

-- Should return empty list for non-existing group
select is(
    list_group_team_members('00000000-0000-0000-0000-000000000099'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'approved_total', 0,
        'members', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
