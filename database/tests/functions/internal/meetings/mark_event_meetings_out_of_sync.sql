-- Tests marking the requested event and session meetings of an event out of sync.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3e7e0000-0000-0000-0000-000000000001'
\set eventCategoryID '3e7e0000-0000-0000-0000-000000000002'
\set eventID '3e7e0000-0000-0000-0000-000000000003'
\set eventNoMeetingID '3e7e0000-0000-0000-0000-000000000004'
\set groupCategoryID '3e7e0000-0000-0000-0000-000000000005'
\set groupID '3e7e0000-0000-0000-0000-000000000006'
\set otherEventID '3e7e0000-0000-0000-0000-000000000007'
\set otherSessionID '3e7e0000-0000-0000-0000-000000000008'
\set requestedSessionID '3e7e0000-0000-0000-0000-000000000009'
\set unrequestedSessionID '3e7e0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Virtual event with a requested meeting that is in sync
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-06-01 12:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', '2030-06-01 10:00:00+00'
));

-- Event without a requested meeting whose earlier sync completed
select fx_event(:'eventNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-06-02 12:00:00+00',
    'meeting_in_sync', true,
    'meeting_requested', false,
    'starts_at', '2030-06-02 10:00:00+00'
));

-- Other virtual event with a requested meeting that is in sync
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-06-03 12:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', '2030-06-03 10:00:00+00'
));

-- Requested session meeting of the other event that is in sync
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    '2030-06-03 11:00:00+00',
    :'otherEventID',
    true,
    'zoom',
    true,
    'Other Event Session',
    :'otherSessionID',
    'virtual',
    '2030-06-03 10:00:00+00'
);

-- Requested session meeting of the event that is in sync
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    '2030-06-01 11:00:00+00',
    :'eventID',
    true,
    'zoom',
    true,
    'Requested Session',
    :'requestedSessionID',
    'virtual',
    '2030-06-01 10:00:00+00'
);

-- Session of the event without a requested meeting whose earlier sync completed
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    '2030-06-01 12:00:00+00',
    :'eventID',
    true,
    false,
    'Unrequested Session',
    :'unrequestedSessionID',
    'virtual',
    '2030-06-01 11:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark the meetings of an event with requested meetings
select lives_ok(
    format('select mark_event_meetings_out_of_sync(%L::uuid)', :'eventID'),
    'Should mark the meetings of an event with requested meetings'
);
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should mark a requested event meeting out of sync'
);
select is(
    (select meeting_in_sync from session where session_id = :'requestedSessionID'),
    false,
    'Should mark requested session meetings out of sync'
);
select is(
    (select meeting_in_sync from session where session_id = :'unrequestedSessionID'),
    true,
    'Should keep the sync state of sessions without a requested meeting'
);
select results_eq(
    format(
        $$
            select e.meeting_in_sync, s.meeting_in_sync
            from event e
            join session s on s.event_id = e.event_id
            where e.event_id = %L::uuid
        $$,
        :'otherEventID'
    ),
    $$ values (true, true) $$,
    'Should leave the meetings of other events unchanged'
);

-- Should keep the sync state of an event without a requested meeting
select lives_ok(
    format('select mark_event_meetings_out_of_sync(%L::uuid)', :'eventNoMeetingID'),
    'Should accept an event without a requested meeting'
);
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    true,
    'Should keep the sync state of an event without a requested meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
