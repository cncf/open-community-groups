-- Tests checking whether events accept scanner check-ins.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '5ea30000-0000-0000-0000-000000000001'
\set communityID '5ea30000-0000-0000-0000-000000000002'
\set endedEventID '5ea30000-0000-0000-0000-000000000003'
\set eventCategoryID '5ea30000-0000-0000-0000-000000000004'
\set groupCategoryID '5ea30000-0000-0000-0000-000000000005'
\set groupID '5ea30000-0000-0000-0000-000000000006'
\set inactiveGroupEventID '5ea30000-0000-0000-0000-000000000007'
\set inactiveGroupID '5ea30000-0000-0000-0000-000000000008'
\set inProgressEventID '5ea30000-0000-0000-0000-000000000009'
\set openEndedTodayEventID '5ea30000-0000-0000-0000-000000000010'
\set openEndedYesterdayEventID '5ea30000-0000-0000-0000-000000000011'
\set unpublishedEventID '5ea30000-0000-0000-0000-000000000012'
\set unscheduledEventID '5ea30000-0000-0000-0000-000000000013'
\set upcomingEventID '5ea30000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the events
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Published upcoming event that was canceled
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event whose explicit end has passed
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 hours',
    'published', true,
    'starts_at', current_timestamp - interval '3 hours'
));

-- Published upcoming event of an inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event in progress until its explicit end
select fx_event(:'inProgressEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'starts_at', current_timestamp - interval '1 hour'
));

-- Published open-ended event starting today in the event timezone
select fx_event(:'openEndedTodayEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('day', current_timestamp at time zone 'Asia/Tokyo') at time zone 'Asia/Tokyo',
    'timezone', 'Asia/Tokyo'
));

-- Published open-ended event that started late yesterday in the event timezone
select fx_event(:'openEndedYesterdayEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (
        date_trunc('day', current_timestamp at time zone 'Asia/Tokyo') - interval '1 hour'
    ) at time zone 'Asia/Tokyo',
    'timezone', 'Asia/Tokyo'
));

-- Unpublished upcoming event
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', false,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event without a start date
select fx_event(:'unscheduledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published open-ended upcoming event
select fx_event(:'upcomingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept in-progress events
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'inProgressEventID'),
    true,
    'Should accept in-progress events'
);

-- Should accept open-ended events before the end of their start day in the event timezone
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'openEndedTodayEventID'),
    true,
    'Should accept open-ended events before the end of their start day in the event timezone'
);

-- Should accept upcoming events
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'upcomingEventID'),
    true,
    'Should accept upcoming events'
);

-- Should reject canceled events
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'canceledEventID'),
    false,
    'Should reject canceled events'
);

-- Should reject ended events
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'endedEventID'),
    false,
    'Should reject ended events'
);

-- Should reject events of inactive groups
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'inactiveGroupEventID'),
    false,
    'Should reject events of inactive groups'
);

-- Should reject open-ended events after the end of their start day in the event timezone
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'openEndedYesterdayEventID'),
    false,
    'Should reject open-ended events after the end of their start day in the event timezone'
);

-- Should reject unpublished events
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'unpublishedEventID'),
    false,
    'Should reject unpublished events'
);

-- Should reject unscheduled events
select is(
    (select is_event_check_in_open(e, g) from event e join "group" g using (group_id) where e.event_id = :'unscheduledEventID'),
    false,
    'Should reject unscheduled events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
