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

-- Baseline active community, categories and users for home stats
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'group2ID', :'communityID', :'groupCategoryID');

-- Inactive community with otherwise-countable rows
select fx_community(:'community3ID', jsonb_build_object('active', false));
select fx_group_category(:'groupCategory2ID', :'community3ID');
select fx_event_category(:'eventCategory2ID', :'community3ID');
select fx_group(:'group4ID', :'community3ID', :'groupCategory2ID');

-- Deleted group excluded from home stats
select fx_group(:'group3ID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Events covering published, unpublished, canceled, deleted, test and inactive-community states
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID');
select fx_event(:'event3ID', :'group2ID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'event4ID', :'group2ID', :'eventCategoryID', jsonb_build_object('deleted', true));
select fx_event(:'event5ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'test_event', true
));
select fx_event(:'event6ID', :'group4ID', :'eventCategory2ID', jsonb_build_object('published', true));

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
-- Expected: groups=2, events=1, groups_members=3, events_attendees=2
select is(
    get_site_home_stats()::jsonb,
    '{
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
