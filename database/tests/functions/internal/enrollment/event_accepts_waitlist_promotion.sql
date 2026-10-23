-- Tests evaluating whether event waitlists accept promotion.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeGroupID 'f3130000-0000-0000-0000-000000000001'
\set canceledEventID 'f3130000-0000-0000-0000-000000000002'
\set communityID 'f3130000-0000-0000-0000-000000000003'
\set datelessEventID 'f3130000-0000-0000-0000-000000000004'
\set eventCategoryID 'f3130000-0000-0000-0000-000000000005'
\set groupCategoryID 'f3130000-0000-0000-0000-000000000006'
\set inactiveGroupEventID 'f3130000-0000-0000-0000-000000000007'
\set inactiveGroupID 'f3130000-0000-0000-0000-000000000008'
\set openEventID 'f3130000-0000-0000-0000-000000000009'
\set registrationClosedEventID 'f3130000-0000-0000-0000-00000000000a'
\set registrationPendingEventID 'f3130000-0000-0000-0000-00000000000b'
\set startedEventID 'f3130000-0000-0000-0000-00000000000c'
\set unpublishedEventID 'f3130000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Active group hosting the gate scenarios
select fx_group(:'activeGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true
));

-- Inactive group whose events never promote waitlists
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false
));

-- Canceled published future event
select fx_event(:'canceledEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'deleted', false,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Published event without dates or a registration window
select fx_event(:'datelessEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'published', true
));

-- Published future event in the inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Published future event whose registration window is open
select fx_event(:'openEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'published', true,
    'registration_ends_at', current_timestamp + interval '1 day',
    'registration_starts_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp + interval '2 days'
));

-- Published future event whose registration window already closed
select fx_event(:'registrationClosedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'registration_starts_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp + interval '2 days'
));

-- Published future event whose registration window has not opened
select fx_event(:'registrationPendingEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'published', true,
    'registration_starts_at', current_timestamp + interval '1 day',
    'starts_at', current_timestamp + interval '2 days'
));

-- Published event in progress without a registration window
select fx_event(:'startedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'starts_at', current_timestamp - interval '1 hour'
));

-- Unpublished future event
select fx_event(:'unpublishedEventID', :'activeGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', false,
    'deleted', false,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'published', false,
    'starts_at', current_timestamp + interval '2 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept published events without dates or a registration window
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'datelessEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    true,
    'Should accept published events without dates or a registration window'
);

-- Should accept published future events with an open registration window
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'openEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    true,
    'Should accept published future events with an open registration window'
);

-- Should reject canceled events
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'canceledEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    false,
    'Should reject canceled events'
);

-- Should reject events in inactive groups
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'inactiveGroupEventID'),
        (select g from "group" g where g.group_id = :'inactiveGroupID')
    ),
    false,
    'Should reject events in inactive groups'
);

-- Should reject events that already started
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'startedEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    false,
    'Should reject events that already started'
);

-- Should reject events whose registration closed
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'registrationClosedEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    false,
    'Should reject events whose registration closed'
);

-- Should reject events whose registration has not opened
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'registrationPendingEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    false,
    'Should reject events whose registration has not opened'
);

-- Should reject unpublished events
select is(
    event_accepts_waitlist_promotion(
        (select e from event e where e.event_id = :'unpublishedEventID'),
        (select g from "group" g where g.group_id = :'activeGroupID')
    ),
    false,
    'Should reject unpublished events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
