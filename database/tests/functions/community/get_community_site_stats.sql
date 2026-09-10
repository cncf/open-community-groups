-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0d040000-0000-0000-0000-000000000001'
\set event1ID '0d040000-0000-0000-0000-000000000002'
\set event2ID '0d040000-0000-0000-0000-000000000003'
\set event3ID '0d040000-0000-0000-0000-000000000004'
\set event4ID '0d040000-0000-0000-0000-000000000005'
\set eventCategoryID '0d040000-0000-0000-0000-000000000006'
\set group1ID '0d040000-0000-0000-0000-000000000007'
\set group2ID '0d040000-0000-0000-0000-000000000008'
\set group3ID '0d040000-0000-0000-0000-000000000009'
\set groupCategoryID '0d040000-0000-0000-0000-000000000010'
\set unknownCommunityID '0d040000-0000-0000-0000-000000000011'
\set user1ID '0d040000-0000-0000-0000-000000000012'
\set user2ID '0d040000-0000-0000-0000-000000000013'
\set user3ID '0d040000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users for community stats
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_group(:'group1ID', :'communityID', :'groupCategoryID');
select fx_group(:'group2ID', :'communityID', :'groupCategoryID');

-- Deleted group excluded from community stats
select fx_group(:'group3ID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Events covering published, unpublished, canceled and deleted stats states
select fx_event(:'event1ID', :'group1ID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'event2ID', :'group1ID', :'eventCategoryID');
select fx_event(:'event3ID', :'group2ID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'event4ID', :'group2ID', :'eventCategoryID', jsonb_build_object('deleted', true));

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

-- Should return zeros for non-existing community
select is(
    get_community_site_stats(:'unknownCommunityID'::uuid)::jsonb,
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
-- - 6 event attendees: 2 confirmed in published event, 1 non-confirmed in
--   published event (should be excluded), 3 in excluded events (should be excluded)
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
