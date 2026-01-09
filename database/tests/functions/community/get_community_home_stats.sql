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
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, active, deleted)
values
    (:'group1ID', 'Seattle Kubernetes Meetup', 'seattle-kubernetes-meetup', :'communityID', :'categoryID', true, false),
    (:'group2ID', 'Cloud Native DevOps Group', 'cloud-native-devops-group', :'communityID', :'categoryID', true, false),
    (:'group3ID', 'Deleted Group', 'deleted-group', :'communityID', :'categoryID', false, true);

-- User
insert into "user" (user_id, email, username, name, email_verified, auth_hash, created_at)
values
    (:'user1ID', 'alice@seattle.cloudnative.org', 'alice-member', 'Alice Johnson', false, 'test_hash', '2024-01-01 00:00:00'),
    (:'user2ID', 'bob@seattle.cloudnative.org', 'bob-member', 'Bob Wilson', false, 'test_hash', '2024-01-01 00:00:00'),
    (:'user3ID', 'charlie@seattle.cloudnative.org', 'charlie-member', 'Charlie Brown', false, 'test_hash', '2024-01-01 00:00:00');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values ('00000000-0000-0000-0000-000000000061', 'Tech Talks', 'tech-talks', :'communityID');

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
    (:'event1ID', 'KubeCon Seattle 2024', 'kubecon-seattle-2024', 'Annual Kubernetes conference', 'America/Los_Angeles', :'eventCategoryID', 'in-person', :'group1ID', false, false, true),
    (:'event2ID', 'Unpublished Event', 'unpublished-event', 'Draft event', 'America/Los_Angeles', :'eventCategoryID', 'in-person', :'group1ID', false, false, false),
    (:'event3ID', 'Canceled Event', 'canceled-event', 'Canceled event', 'America/Los_Angeles', :'eventCategoryID', 'in-person', :'group2ID', true, false, false),
    (:'event4ID', 'Deleted Event', 'deleted-event', 'Deleted event', 'America/Los_Angeles', :'eventCategoryID', 'in-person', :'group2ID', false, true, false);

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
    get_community_home_stats('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
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
    get_community_home_stats('00000000-0000-0000-0000-999999999999'::uuid)::jsonb,
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
    (get_community_home_stats(:'communityID'::uuid)::jsonb),
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
