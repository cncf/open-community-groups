-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'
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
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'community1ID', true, 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant community', 'https://example.com/logo1.png', 'https://example.com/banner_mobile1.png', 'https://example.com/banner1.png'),
    (:'community2ID', true, 'cloud-native-portland', 'Cloud Native Portland', 'Another vibrant community', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png'),
    (:'community3ID', false, 'inactive-community', 'Inactive Community', 'An inactive community', 'https://example.com/logo3.png', 'https://example.com/banner_mobile3.png', 'https://example.com/banner3.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'community1ID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, active, deleted)
values
    (:'group1ID', 'Seattle Kubernetes Meetup', 'seattle-kubernetes-meetup', :'community1ID', :'categoryID', true, false),
    (:'group2ID', 'Cloud Native DevOps Group', 'cloud-native-devops-group', :'community1ID', :'categoryID', true, false),
    (:'group3ID', 'Deleted Group', 'deleted-group', :'community1ID', :'categoryID', false, true);

-- User
insert into "user" (user_id, email, username, name, email_verified, auth_hash, created_at)
values
    (:'user1ID', 'alice@seattle.cloudnative.org', 'alice-member', 'Alice Johnson', false, 'test_hash', '2024-01-01 00:00:00'),
    (:'user2ID', 'bob@seattle.cloudnative.org', 'bob-member', 'Bob Wilson', false, 'test_hash', '2024-01-01 00:00:00'),
    (:'user3ID', 'charlie@seattle.cloudnative.org', 'charlie-member', 'Charlie Brown', false, 'test_hash', '2024-01-01 00:00:00');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values ('00000000-0000-0000-0000-000000000061', 'Tech Talks', 'tech-talks', :'community1ID');

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
-- - 3 communities: 2 active (community1, community2), 1 inactive (community3)
-- - 3 groups: 2 active (group1, group2), 1 deleted (group3)
-- - 4 events: 1 published (event1), 1 unpublished (event2), 1 canceled (event3), 1 deleted (event4)
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
