-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '9a020000-0000-0000-0000-000000000001'
\set community2ID '9a020000-0000-0000-0000-000000000002'
\set community3ID '9a020000-0000-0000-0000-000000000003'
\set eventID '9a020000-0000-0000-0000-000000000004'
\set event2ID '9a020000-0000-0000-0000-000000000005'
\set event3ID '9a020000-0000-0000-0000-000000000006'
\set event4ID '9a020000-0000-0000-0000-000000000007'
\set event5ID '9a020000-0000-0000-0000-000000000008'
\set event6ID '9a020000-0000-0000-0000-000000000009'
\set eventCategoryID '9a020000-0000-0000-0000-000000000010'
\set eventCategory2ID '9a020000-0000-0000-0000-000000000011'
\set groupID '9a020000-0000-0000-0000-000000000012'
\set group2ID '9a020000-0000-0000-0000-000000000013'
\set group3ID '9a020000-0000-0000-0000-000000000014'
\set group4ID '9a020000-0000-0000-0000-000000000015'
\set groupCategoryID '9a020000-0000-0000-0000-000000000016'
\set groupCategory2ID '9a020000-0000-0000-0000-000000000017'
\set user1ID '9a020000-0000-0000-0000-000000000018'
\set user2ID '9a020000-0000-0000-0000-000000000019'
\set user3ID '9a020000-0000-0000-0000-000000000020'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'communityID',
        'site-home-stats-primary',
        'Site Home Stats Primary',
        'Primary community for home stats tests',
        true,
        'https://example.com/site-home-stats-primary-banner-mobile.png',
        'https://example.com/site-home-stats-primary-banner.png',
        'https://example.com/site-home-stats-primary-logo.png'
    ),
    (
        :'community2ID',
        'site-home-stats-secondary',
        'Site Home Stats Secondary',
        'Secondary community for home stats tests',
        true,
        'https://example.com/site-home-stats-secondary-banner-mobile.png',
        'https://example.com/site-home-stats-secondary-banner.png',
        'https://example.com/site-home-stats-secondary-logo.png'
    ),
    (
        :'community3ID',
        'inactive-site-home-stats',
        'Inactive Site Home Stats',
        'Inactive community for home stats tests',
        false,
        'https://example.com/inactive-site-home-stats-banner-mobile.png',
        'https://example.com/inactive-site-home-stats-banner.png',
        'https://example.com/inactive-site-home-stats-logo.png'
    );

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'communityID', 'Technology'),
    (:'groupCategory2ID', :'community3ID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategoryID', :'communityID', 'Meetups'),
    (:'eventCategory2ID', :'community3ID', 'Meetups');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    created_at,
    name
)
values
    (:'user1ID', gen_random_bytes(32), 'home-stats-user1@example.com',
        true, 'home-stats-user-one', '2024-01-01 00:00:00', 'Home Stats User One'),
    (:'user2ID', gen_random_bytes(32), 'home-stats-user2@example.com',
        true, 'home-stats-user-two', '2024-01-01 00:00:00', 'Home Stats User Two'),
    (:'user3ID', gen_random_bytes(32), 'home-stats-user3@example.com',
        true, 'home-stats-user-three', '2024-01-01 00:00:00', 'Home Stats User Three');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
)
values
    (:'groupID', :'communityID', :'groupCategoryID',
        'Home Stats Group One', 'home-stats-group-one', true, false),
    (:'group2ID', :'communityID', :'groupCategoryID',
        'Home Stats Group Two', 'home-stats-group-two', true, false),
    (:'group3ID', :'communityID', :'groupCategoryID',
        'Deleted Home Stats Group', 'deleted-home-stats-group', false, true),
    (:'group4ID', :'community3ID', :'groupCategory2ID',
        'Inactive Community Home Stats Group', 'inactive-community-home-stats-group', true, false);

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    test_event,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    canceled,
    deleted,
    published
) values
    (:'eventID', 'Published Home Stats Event', 'published-home-stats-event',
        'Published event for home stats tests', false, 'UTC', :'eventCategoryID',
        'in-person', :'groupID', false, false, true),
    (:'event2ID', 'Unpublished Home Stats Event', 'unpublished-home-stats-event',
        'Unpublished event for home stats tests', false, 'UTC', :'eventCategoryID',
        'in-person', :'groupID', false, false, false),
    (:'event3ID', 'Canceled Home Stats Event', 'canceled-home-stats-event',
        'Canceled event for home stats tests', false, 'UTC', :'eventCategoryID',
        'in-person', :'group2ID', true, false, false),
    (:'event4ID', 'Deleted Home Stats Event', 'deleted-home-stats-event',
        'Deleted event for home stats tests', false, 'UTC', :'eventCategoryID',
        'in-person', :'group2ID', false, true, false),
    (:'event5ID', 'Test Home Stats Event', 'test-home-stats-event',
        'Test event for home stats tests', true, 'UTC', :'eventCategoryID',
        'in-person', :'groupID', false, false, true),
    (:'event6ID', 'Inactive Community Home Stats Event',
        'inactive-community-home-stats-event', 'Inactive community event for home stats tests',
        false, 'UTC', :'eventCategory2ID', 'in-person', :'group4ID', false, false, true);

-- Group Member
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00'),
    (:'groupID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group3ID', :'user3ID', '2024-01-01 00:00:00'),
    (:'group4ID', :'user3ID', '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'eventID', :'user1ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'eventID', :'user3ID', 'invitation-pending', '2024-01-01 00:00:00'),
    (:'event2ID', :'user1ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event3ID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event4ID', :'user3ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event5ID', :'user3ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event6ID', :'user1ID', 'confirmed', '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude inactive communities, deleted groups and unpublished/canceled/deleted events
-- Data setup:
-- - 3 communities: 2 active (community, community2), 1 inactive (community3)
-- - 4 groups: 2 active (group, group2), 1 deleted (group3), 1 in inactive community (group4)
-- - 6 events: 1 published (event), 1 unpublished (event2), 1 canceled (event3),
--   1 deleted (event4), 1 test event (event5), 1 in inactive community (event6)
-- - 5 group members: 3 in active groups, 1 in deleted group, 1 in inactive
--   community group (should be excluded)
-- - 8 event attendees: 2 confirmed in published event, 1 non-confirmed in
--   published event (should be excluded), 5 in excluded events (should be excluded)
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
