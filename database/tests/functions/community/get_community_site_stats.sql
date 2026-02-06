-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000051'
\set event2ID '00000000-0000-0000-0000-000000000052'
\set event3ID '00000000-0000-0000-0000-000000000053'
\set event4ID '00000000-0000-0000-0000-000000000054'
\set eventCategoryID '00000000-0000-0000-0000-000000000061'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set group3ID '00000000-0000-0000-0000-000000000033'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set user3ID '00000000-0000-0000-0000-000000000043'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, active, deleted)
values
    (:'group1ID', 'G1', 'g1', :'communityID', :'categoryID', true, false),
    (:'group2ID', 'G2', 'g2', :'communityID', :'categoryID', true, false),
    (:'group3ID', 'G3', 'g3', :'communityID', :'categoryID', false, true);

-- User
insert into "user" (user_id, email, username, name, email_verified, auth_hash, created_at)
values
    (:'user1ID', 'u1@e', 'u1', 'U1', true, gen_random_bytes(32), '2024-01-01 00:00:00'),
    (:'user2ID', 'u2@e', 'u2', 'U2', true, gen_random_bytes(32), '2024-01-01 00:00:00'),
    (:'user3ID', 'u3@e', 'u3', 'U3', true, gen_random_bytes(32), '2024-01-01 00:00:00');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Cat', 'cat', :'communityID');

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
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'group1ID', false, false, true),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'group1ID', false, false, false),
    (:'event3ID', 'E3', 'e3', 'd', 'UTC', :'eventCategoryID', 'in-person', :'group2ID', true, false, false),
    (:'event4ID', 'E4', 'e4', 'd', 'UTC', :'eventCategoryID', 'in-person', :'group2ID', false, true, false);

-- Group Member
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group3ID', :'user3ID', '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, created_at)
values
    (:'event1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'event1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'event2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'event3ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'event4ID', :'user3ID', '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct community statistics as JSON
select is(
    get_community_site_stats('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '{
        "events": 1,
        "groups": 2,
        "groups_members": 3,
        "events_attendees": 2
    }'::jsonb,
    'Should return correct community statistics as JSON'
);

-- Should return zeros for non-existing community
select is(
    get_community_site_stats('00000000-0000-0000-0000-999999999999'::uuid)::jsonb,
    '{
        "events": 0,
        "groups": 0,
        "groups_members": 0,
        "events_attendees": 0
    }'::jsonb,
    'Should return zeros for non-existing community'
);

-- Should exclude deleted groups and unpublished/canceled/deleted events
-- Data setup:
-- - 3 groups: 2 active (group1, group2), 1 deleted (group3)
-- - 4 events: 1 published (event1), 1 unpublished (event2), 1 canceled (event3), 1 deleted (event4)
-- - 4 group members: 3 in active groups, 1 in deleted group (should be excluded)
-- - 5 event attendees: 2 in published event, 3 in excluded events (should be excluded)
-- Expected: groups=2, events=1, groups_members=3, events_attendees=2
select is(
    (get_community_site_stats(:'communityID'::uuid)::jsonb),
    '{
        "events": 1,
        "groups": 2,
        "groups_members": 3,
        "events_attendees": 2
    }'::jsonb,
    'Should exclude deleted groups and unpublished/canceled/deleted events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
