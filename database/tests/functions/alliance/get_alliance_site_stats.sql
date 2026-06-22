-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0d040000-0000-0000-0000-000000000001'
\set event1ID '0d040000-0000-0000-0000-000000000002'
\set event2ID '0d040000-0000-0000-0000-000000000003'
\set event3ID '0d040000-0000-0000-0000-000000000004'
\set event4ID '0d040000-0000-0000-0000-000000000005'
\set eventCategoryID '0d040000-0000-0000-0000-000000000006'
\set group1ID '0d040000-0000-0000-0000-000000000007'
\set group2ID '0d040000-0000-0000-0000-000000000008'
\set group3ID '0d040000-0000-0000-0000-000000000009'
\set groupCategoryID '0d040000-0000-0000-0000-000000000010'
\set unknownAllianceID '0d040000-0000-0000-0000-000000000011'
\set user1ID '0d040000-0000-0000-0000-000000000012'
\set user2ID '0d040000-0000-0000-0000-000000000013'
\set user3ID '0d040000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'alliance-site-stats',
    'Alliance Site Stats',
    'Alliance used for site stats tests',
    'https://example.com/alliance-site-stats-banner-mobile.png',
    'https://example.com/alliance-site-stats-banner.png',
    'https://example.com/alliance-site-stats-logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
)
values
    (:'group1ID', :'allianceID', :'groupCategoryID',
        'Site Stats Group One', 'site-stats-group-one', true, false),
    (:'group2ID', :'allianceID', :'groupCategoryID',
        'Site Stats Group Two', 'site-stats-group-two', true, false),
    (:'group3ID', :'allianceID', :'groupCategoryID',
        'Deleted Site Stats Group', 'deleted-site-stats-group', false, true);

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
    (:'user1ID', gen_random_bytes(32), 'stats-user1@example.com',
        true, 'stats-user-one', '2024-01-01 00:00:00', 'Stats User One'),
    (:'user2ID', gen_random_bytes(32), 'stats-user2@example.com',
        true, 'stats-user-two', '2024-01-01 00:00:00', 'Stats User Two'),
    (:'user3ID', gen_random_bytes(32), 'stats-user3@example.com',
        true, 'stats-user-three', '2024-01-01 00:00:00', 'Stats User Three');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetups');

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
    (:'event1ID', 'Published Stats Event', 'published-stats-event',
        'Published event for stats tests', 'UTC', :'eventCategoryID',
        'in-person', :'group1ID', false, false, true),
    (:'event2ID', 'Unpublished Stats Event', 'unpublished-stats-event',
        'Unpublished event for stats tests', 'UTC', :'eventCategoryID',
        'in-person', :'group1ID', false, false, false),
    (:'event3ID', 'Canceled Stats Event', 'canceled-stats-event',
        'Canceled event for stats tests', 'UTC', :'eventCategoryID',
        'in-person', :'group2ID', true, false, false),
    (:'event4ID', 'Deleted Stats Event', 'deleted-stats-event',
        'Deleted event for stats tests', 'UTC', :'eventCategoryID',
        'in-person', :'group2ID', false, true, false);

-- Group Member
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group3ID', :'user3ID', '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'event1ID', :'user1ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event1ID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event1ID', :'user3ID', 'invitation-pending', '2024-01-01 00:00:00'),
    (:'event2ID', :'user1ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event3ID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event4ID', :'user3ID', 'confirmed', '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return zeros for non-existing alliance
select is(
    get_alliance_site_stats(:'unknownAllianceID'::uuid)::jsonb,
    '{
        "events": 0,
        "groups": 0,
        "groups_members": 0,
        "events_attendees": 0
    }'::jsonb,
    'Should return zeros for non-existing alliance'
);

-- Should exclude deleted groups and unpublished/canceled/deleted events
-- Data setup:
-- - 3 groups: 2 active (group1, group2), 1 deleted (group3)
-- - 4 events: 1 published (event1), 1 unpublished (event2), 1 canceled (event3), 1 deleted (event4)
-- - 4 group members: 3 in active groups, 1 in deleted group (should be excluded)
-- - 6 event attendees: 2 confirmed in published event, 1 non-confirmed in
--   published event (should be excluded), 3 in excluded events (should be excluded)
-- Expected: groups=2, events=1, groups_members=3, events_attendees=2
select is(
    (get_alliance_site_stats(:'allianceID'::uuid)::jsonb),
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
