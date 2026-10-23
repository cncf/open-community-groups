-- Tests computing the community site page statistics.

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
\set event3ID '0d040000-0000-0000-0000-000000000004'
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

-- Community owning the counted rows
select fx_community(:'communityID');

-- User attending the listed event and a member of both active groups
select fx_user(:'user1ID');

-- User attending the listed event and the canceled event
select fx_user(:'user2ID');

-- User with an excluded membership and a pending invitation
select fx_user(:'user3ID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group owning the listed event
select fx_group(:'group1ID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Active group owning the canceled event and co-hosting the listed event
select fx_group(:'group2ID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Inactive group excluded from community stats
select fx_group(:'group3ID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Listed event
select fx_event(:'event1ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
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

-- Group members across counted and excluded groups
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group3ID', :'user3ID', '2024-01-01 00:00:00');

-- Event attendees across counted and excluded events
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'event1ID', :'user1ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event1ID', :'user2ID', 'confirmed', '2024-01-01 00:00:00'),
    (:'event1ID', :'user3ID', 'invitation-pending', '2024-01-01 00:00:00'),
    (:'event3ID', :'user2ID', 'confirmed', '2024-01-01 00:00:00');

-- Approved co-host credit that must not duplicate community event counts
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    current_timestamp,
    'approved',
    :'event1ID',
    :'group2ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude inactive groups and unlisted events
-- Data setup:
-- - 3 groups: 2 active (group1, group2), 1 inactive (group3)
-- - 2 events: 1 listed (event1), 1 canceled (event3)
-- - 1 approved co-host credit for event1 (owner-only attribution)
-- - 4 group members: 3 in active groups, 1 in inactive group (should be excluded)
-- - 4 event attendees: 2 confirmed in the listed event, 1 non-confirmed in the
--   listed event (should be excluded), 1 in the canceled event (should be excluded)
-- Expected: groups=2, events=1, groups_members=3, events_attendees=2
select is(
    (get_community_site_stats(:'communityID'::uuid)::jsonb),
    '{
        "events": 1,
        "events_attendees": 2,
        "groups": 2,
        "groups_members": 3
    }'::jsonb,
    'Should exclude inactive groups and unlisted events'
);

-- Should return zeros for non-existing community
select is(
    get_community_site_stats(:'unknownCommunityID'::uuid)::jsonb,
    '{
        "events": 0,
        "events_attendees": 0,
        "groups": 0,
        "groups_members": 0
    }'::jsonb,
    'Should return zeros for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
