-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event2ID '00000000-0000-0000-0000-000000000052'
\set event3ID '00000000-0000-0000-0000-000000000053'
\set event4ID '00000000-0000-0000-0000-000000000054'
\set eventCategoryID '00000000-0000-0000-0000-000000000061'
\set eventID '00000000-0000-0000-0000-000000000051'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set groupID '00000000-0000-0000-0000-000000000031'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set user3ID '00000000-0000-0000-0000-000000000043'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'communityID', true, 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png'),
    (:'community2ID', true, 'c2', 'C2', 'd', 'https://e/logo2.png', 'https://e/bm2.png', 'https://e/b2.png'),
    (:'community3ID', false, 'c3', 'C3', 'd', 'https://e/logo3.png', 'https://e/bm3.png', 'https://e/b3.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, active, deleted)
values
    (:'groupID', 'G1', 'g1', :'communityID', :'categoryID', true, false),
    (:'group2ID', 'G2', 'g2', :'communityID', :'categoryID', true, false),
    (:'group3ID', 'G3', 'g3', :'communityID', :'categoryID', false, true);

-- User
insert into "user" (user_id, email, username, name, email_verified, auth_hash, created_at)
values
    (:'user1ID', 'u1@e', 'u1', 'U1', true, gen_random_bytes(32), '2024-01-01 00:00:00'),
    (:'user2ID', 'u2@e', 'u2', 'U2', true, gen_random_bytes(32), '2024-01-01 00:00:00'),
    (:'user3ID', 'u3@e', 'u3', 'U3', true, gen_random_bytes(32), '2024-01-01 00:00:00');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Cat', :'communityID');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    canceled,
    deleted,
    published
) values
    (:'eventID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false),
    (:'event3ID', 'E3', 'e3', 'd', 'UTC', :'eventCategoryID', 'in-person', :'group2ID', true, false, false),
    (:'event4ID', 'E4', 'e4', 'd', 'UTC', :'eventCategoryID', 'in-person', :'group2ID', false, true, false);

-- Group Member
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00'),
    (:'groupID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group3ID', :'user3ID', '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, created_at)
values
    (:'eventID', :'user1ID', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', '2024-01-01 00:00:00'),
    (:'event2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'event3ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'event4ID', :'user3ID', '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct site statistics as JSON
select is(
    get_site_home_stats()::jsonb,
    '{
        "communities": 2,
        "events": 1,
        "events_attendees": 2,
        "groups": 2,
        "groups_members": 3
    }'::jsonb,
    'Should return correct site statistics as JSON'
);

-- Should exclude inactive communities, deleted groups and unpublished/canceled/deleted events
-- Data setup:
-- - 3 communities: 2 active (community, community2), 1 inactive (community3)
-- - 3 groups: 2 active (group, group2), 1 deleted (group3)
-- - 4 events: 1 published (event), 1 unpublished (event2), 1 canceled (event3), 1 deleted (event4)
-- - 4 group members: 3 in active groups, 1 in deleted group (should be excluded)
-- - 5 event attendees: 2 in published event, 3 in excluded events (should be excluded)
-- Expected: communities=2, groups=2, events=1, groups_members=3, events_attendees=2
select is(
    get_site_home_stats()::jsonb,
    '{
        "communities": 2,
        "events": 1,
        "events_attendees": 2,
        "groups": 2,
        "groups_members": 3
    }'::jsonb,
    'Should exclude inactive communities, deleted groups and unpublished/canceled/deleted events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
