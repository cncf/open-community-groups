-- Tests computing the site home page statistics.

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
\set event3ID '9a020000-0000-0000-0000-000000000006'
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

-- Active community owning the counted rows
select fx_community(:'communityID');

-- Second active community without groups
select fx_community(:'community2ID');

-- Inactive community with otherwise-countable rows
select fx_community(:'community3ID', jsonb_build_object('active', false));

-- User attending the listed event and the inactive community event
select fx_user(:'user1ID');

-- User attending the listed event and the canceled event
select fx_user(:'user2ID');

-- User with excluded memberships and a pending invitation
select fx_user(:'user3ID');

-- Event category in the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category in the inactive community
select fx_event_category(:'eventCategory2ID', :'community3ID');

-- Group category in the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category in the inactive community
select fx_group_category(:'groupCategory2ID', :'community3ID');

-- Active group owning the listed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Active group owning the canceled event and co-hosting the listed event
select fx_group(:'group2ID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Inactive group excluded from home stats
select fx_group(:'group3ID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Active group in the inactive community
select fx_group(:'group4ID', :'community3ID', :'groupCategory2ID', jsonb_build_object('active', true));

-- Listed event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'published', true,
    'test_event', false
));

-- Published event that was canceled
select fx_event(:'event3ID', :'group2ID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'test_event', false
));

-- Published event in the inactive community
select fx_event(:'event6ID', :'group4ID', :'eventCategory2ID', jsonb_build_object(
    'canceled', false,
    'published', true,
    'test_event', false
));

-- Group members across counted and excluded groups
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'user1ID', '2024-01-01 00:00:00'),
    (:'groupID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group3ID', :'user3ID', '2024-01-01 00:00:00'),
    (:'group4ID', :'user3ID', '2024-01-01 00:00:00');

-- Event attendees across counted and excluded events
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'eventID', :'user1ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'eventID', :'user3ID', 'invitation-pending', '2024-01-01 00:00:00'),
    (:'event3ID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event6ID', :'user1ID', 'confirmed', '2024-01-01 00:00:00');

-- Approved co-host credit that must not duplicate home event counts
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    current_timestamp,
    'approved',
    :'eventID',
    :'group2ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude inactive communities, inactive groups and unlisted events
-- Data setup:
-- - 3 communities: 2 active (community, community2), 1 inactive (community3)
-- - 4 groups: 2 active (group, group2), 1 inactive (group3), 1 in inactive community (group4)
-- - 3 events: 1 listed (event), 1 canceled (event3), 1 in inactive community (event6)
-- - 1 approved co-host credit for the listed event (owner-only attribution)
-- - 5 group members: 3 in active groups, 1 in inactive group, 1 in inactive
--   community group (should be excluded)
-- - 5 event attendees: 2 confirmed in the listed event, 1 non-confirmed in the
--   listed event (should be excluded), 2 in excluded events (should be excluded)
-- Expected: groups=2, events=1, groups_members=3, events_attendees=2
select is(
    get_site_home_stats()::jsonb,
    '{
        "events": 1,
        "events_attendees": 2,
        "groups": 2,
        "groups_members": 3
    }'::jsonb,
    'Should exclude inactive communities, inactive groups and unlisted events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
