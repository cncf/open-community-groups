-- Tests re-queuing provider meeting deletions lost by repeated saves.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(23);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set failedDeletionEventID '96000000-0000-0000-0000-000000000003'
\set manualUrlEventID '96000000-0000-0000-0000-000000000008'
\set manualUrlSessionID '96000000-0000-0000-0000-000000000011'
\set noMeetingEventID '96000000-0000-0000-0000-000000000013'
\set nullRequestedEventID '96000000-0000-0000-0000-000000000029'
\set nullRequestedManualUrlEventID '96000000-0000-0000-0000-000000000049'
\set nullRequestedManualUrlSessionID '96000000-0000-0000-0000-000000000052'
\set nullRequestedOtherUrlEventID '96000000-0000-0000-0000-000000000059'
\set nullRequestedOtherUrlSessionID '96000000-0000-0000-0000-000000000062'
\set nullRequestedPendingEventID '96000000-0000-0000-0000-000000000054'
\set nullRequestedPendingSessionID '96000000-0000-0000-0000-000000000057'
\set nullRequestedRecordedEventID '96000000-0000-0000-0000-000000000044'
\set nullRequestedRecordedSessionID '96000000-0000-0000-0000-000000000047'
\set nullRequestedSessionID '96000000-0000-0000-0000-000000000032'
\set otherUrlEventID '96000000-0000-0000-0000-000000000039'
\set otherUrlSessionID '96000000-0000-0000-0000-000000000042'
\set outOfBoundsSessionID '96000000-0000-0000-0000-000000000022'
\set recordedEventID '96000000-0000-0000-0000-000000000024'
\set recordedSessionID '96000000-0000-0000-0000-000000000027'
\set requestedEventID '96000000-0000-0000-0000-000000000034'
\set requestedSessionID '96000000-0000-0000-0000-000000000037'
\set requeuedEventID '96000000-0000-0000-0000-000000000015'
\set requeuedSessionID '96000000-0000-0000-0000-000000000018'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep the pending meeting deletion of a session with an unset meeting request
select is(
    (select meeting_in_sync from session where session_id = :'nullRequestedPendingSessionID'),
    false,
    'Should keep the pending meeting deletion of a session with an unset meeting request'
);

-- Should keep the pending meeting deletion of a session with an unset meeting request despite an unrelated manual URL
select is(
    (select meeting_in_sync from session where session_id = :'nullRequestedOtherUrlSessionID'),
    false,
    'Should keep the pending meeting deletion of a session with an unset meeting request despite an unrelated manual URL'
);

-- Should keep the pending meeting deletion of an event with an unset meeting request
select is(
    (select meeting_in_sync from event where event_id = :'nullRequestedPendingEventID'),
    false,
    'Should keep the pending meeting deletion of an event with an unset meeting request'
);

-- Should keep the pending meeting deletion of an event with an unset meeting request despite an unrelated manual URL
select is(
    (select meeting_in_sync from event where event_id = :'nullRequestedOtherUrlEventID'),
    false,
    'Should keep the pending meeting deletion of an event with an unset meeting request despite an unrelated manual URL'
);

-- Should keep the sync state of an event whose meeting deletion failed
select is(
    (select meeting_in_sync from event where event_id = :'failedDeletionEventID'),
    true,
    'Should keep the sync state of an event whose meeting deletion failed'
);

-- Should leave a session reusing the leaked meeting URL without sync work
select is(
    (select meeting_in_sync from session where session_id = :'manualUrlSessionID'),
    null::boolean,
    'Should leave a session reusing the leaked meeting URL without sync work'
);

-- Should leave a session whose leaked meeting has recordings without sync work
select is(
    (select meeting_in_sync from session where session_id = :'recordedSessionID'),
    null::boolean,
    'Should leave a session whose leaked meeting has recordings without sync work'
);

-- Should leave a session with a requested meeting without sync work
select is(
    (select meeting_in_sync from session where session_id = :'requestedSessionID'),
    null::boolean,
    'Should leave a session with a requested meeting without sync work'
);

-- Should leave a session with an unset meeting request without sync work
select is(
    (select meeting_in_sync from session where session_id = :'nullRequestedSessionID'),
    null::boolean,
    'Should leave a session with an unset meeting request without sync work'
);

-- Should leave an event reusing the leaked meeting URL without sync work
select is(
    (select meeting_in_sync from event where event_id = :'manualUrlEventID'),
    null::boolean,
    'Should leave an event reusing the leaked meeting URL without sync work'
);

-- Should leave an event whose leaked meeting has recordings without sync work
select is(
    (select meeting_in_sync from event where event_id = :'recordedEventID'),
    null::boolean,
    'Should leave an event whose leaked meeting has recordings without sync work'
);

-- Should leave an event with a requested meeting without sync work
select is(
    (select meeting_in_sync from event where event_id = :'requestedEventID'),
    null::boolean,
    'Should leave an event with a requested meeting without sync work'
);

-- Should leave an event with an unset meeting request without sync work
select is(
    (select meeting_in_sync from event where event_id = :'nullRequestedEventID'),
    null::boolean,
    'Should leave an event with an unset meeting request without sync work'
);

-- Should leave an event without a linked meeting without sync work
select is(
    (select meeting_in_sync from event where event_id = :'noMeetingEventID'),
    null::boolean,
    'Should leave an event without a linked meeting without sync work'
);

-- Should requeue the lost event meeting deletion
select is(
    (select meeting_in_sync from event where event_id = :'requeuedEventID'),
    false,
    'Should requeue the lost event meeting deletion'
);

-- Should requeue the lost event meeting deletion despite an unrelated manual URL
select is(
    (select meeting_in_sync from event where event_id = :'otherUrlEventID'),
    false,
    'Should requeue the lost event meeting deletion despite an unrelated manual URL'
);

-- Should requeue the lost meeting deletion of a session outside its event bounds
select is(
    (select meeting_in_sync from session where session_id = :'outOfBoundsSessionID'),
    false,
    'Should requeue the lost meeting deletion of a session outside its event bounds'
);

-- Should requeue the lost session meeting deletion
select is(
    (select meeting_in_sync from session where session_id = :'requeuedSessionID'),
    false,
    'Should requeue the lost session meeting deletion'
);

-- Should requeue the lost session meeting deletion despite an unrelated manual URL
select is(
    (select meeting_in_sync from session where session_id = :'otherUrlSessionID'),
    false,
    'Should requeue the lost session meeting deletion despite an unrelated manual URL'
);

-- Should stop the unset-request event meeting deletion reusing the meeting URL
select is(
    (select meeting_in_sync from event where event_id = :'nullRequestedManualUrlEventID'),
    null::boolean,
    'Should stop the unset-request event meeting deletion reusing the meeting URL'
);

-- Should stop the unset-request event meeting deletion with recordings
select is(
    (select meeting_in_sync from event where event_id = :'nullRequestedRecordedEventID'),
    null::boolean,
    'Should stop the unset-request event meeting deletion with recordings'
);

-- Should stop the unset-request session meeting deletion reusing the meeting URL
select is(
    (select meeting_in_sync from session where session_id = :'nullRequestedManualUrlSessionID'),
    null::boolean,
    'Should stop the unset-request session meeting deletion reusing the meeting URL'
);

-- Should stop the unset-request session meeting deletion with recordings
select is(
    (select meeting_in_sync from session where session_id = :'nullRequestedRecordedSessionID'),
    null::boolean,
    'Should stop the unset-request session meeting deletion with recordings'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
