-- Tests locking events that are still open to attendee and organizer actions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'f2020000-0000-0000-0000-000000000001'
\set communityID 'f2020000-0000-0000-0000-000000000002'
\set deletedEventID 'f2020000-0000-0000-0000-000000000003'
\set draftEventID 'f2020000-0000-0000-0000-000000000004'
\set endedEventID 'f2020000-0000-0000-0000-000000000005'
\set eventCategoryID 'f2020000-0000-0000-0000-000000000006'
\set groupCategoryID 'f2020000-0000-0000-0000-000000000007'
\set groupID 'f2020000-0000-0000-0000-000000000008'
\set inactiveGroupEventID 'f2020000-0000-0000-0000-000000000009'
\set inactiveGroupID 'f2020000-0000-0000-0000-00000000000a'
\set liveEventID 'f2020000-0000-0000-0000-00000000000b'
\set ongoingEventID 'f2020000-0000-0000-0000-00000000000f'
\set otherCommunityID 'f2020000-0000-0000-0000-00000000000c'
\set otherGroupID 'f2020000-0000-0000-0000-00000000000d'
\set startOnlyEventID 'f2020000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, categories and groups
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false
));

-- Published upcoming event
select fx_event(:'liveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event that already started but has no end date
select fx_event(:'startOnlyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp - interval '1 hour'
));

-- Published event in progress
select fx_event(:'ongoingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'starts_at', current_timestamp - interval '1 hour'
));

-- Unpublished upcoming event
select fx_event(:'draftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', false,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event that already ended
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 hour',
    'published', true,
    'starts_at', current_timestamp - interval '2 hours'
));

-- Canceled event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Deleted event
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'published', false,
    'starts_at', current_timestamp + interval '1 day'
));

-- Event in an inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the event row when scoped by community
select is(
    (select (lock_active_event(:'communityID', null, :'liveEventID', true)).event_id),
    :'liveEventID'::uuid,
    'Should return the event row when scoped by community'
);

-- Should return the event row when scoped by group
select is(
    (select (lock_active_event(null, :'groupID', :'liveEventID', true)).group_id),
    :'groupID'::uuid,
    'Should return the event row when scoped by group'
);

-- Should keep events in progress open
select is(
    (select (lock_active_event(:'communityID', null, :'ongoingEventID', true)).event_id),
    :'ongoingEventID'::uuid,
    'Should keep events in progress open'
);

-- Should treat started events without an end date as over
select throws_ok(
    $$ select lock_active_event('f2020000-0000-0000-0000-000000000002', null, 'f2020000-0000-0000-0000-00000000000e', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should treat started events without an end date as over'
);

-- Should return unpublished events when publication is not required
select is(
    (select (lock_active_event(null, :'groupID', :'draftEventID', false)).published),
    false,
    'Should return unpublished events when publication is not required'
);

-- Should reject unpublished events when publication is required
select throws_ok(
    $$ select lock_active_event(null, 'f2020000-0000-0000-0000-000000000008', 'f2020000-0000-0000-0000-000000000004', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject unpublished events when publication is required'
);

-- Should reject events from another community
select throws_ok(
    $$ select lock_active_event('f2020000-0000-0000-0000-00000000000c', null, 'f2020000-0000-0000-0000-00000000000b', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject events from another community'
);

-- Should reject events from another group
select throws_ok(
    $$ select lock_active_event(null, 'f2020000-0000-0000-0000-00000000000d', 'f2020000-0000-0000-0000-00000000000b', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject events from another group'
);

-- Should reject events that already ended
select throws_ok(
    $$ select lock_active_event('f2020000-0000-0000-0000-000000000002', null, 'f2020000-0000-0000-0000-000000000005', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject events that already ended'
);

-- Should reject canceled events
select throws_ok(
    $$ select lock_active_event('f2020000-0000-0000-0000-000000000002', null, 'f2020000-0000-0000-0000-000000000001', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject deleted events
select throws_ok(
    $$ select lock_active_event('f2020000-0000-0000-0000-000000000002', null, 'f2020000-0000-0000-0000-000000000003', false) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject deleted events'
);

-- Should reject events whose group is inactive
select throws_ok(
    $$ select lock_active_event('f2020000-0000-0000-0000-000000000002', null, 'f2020000-0000-0000-0000-000000000009', true) $$,
    'OCG01',
    'event not found or inactive',
    'Should reject events whose group is inactive'
);

-- Should require a scope
select throws_ok(
    $$ select lock_active_event(null, null, 'f2020000-0000-0000-0000-00000000000b', true) $$,
    'lock_active_event requires a community or group scope',
    'Should require a scope'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
