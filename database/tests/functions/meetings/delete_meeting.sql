-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set allianceID '00000000-0000-0000-0000-000000000001'
\set eventID '00000000-0000-0000-0000-000000000101'
\set eventReassignedClaimID '00000000-0000-0000-0000-000000000103'
\set eventStaleClaimID '00000000-0000-0000-0000-000000000102'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set meetingEventID '00000000-0000-0000-0000-000000000301'
\set meetingEventReassignedID '00000000-0000-0000-0000-000000000305'
\set meetingEventStaleClaimID '00000000-0000-0000-0000-000000000304'
\set meetingOrphanID '00000000-0000-0000-0000-000000000303'
\set meetingSessionID '00000000-0000-0000-0000-000000000302'
\set sessionID '00000000-0000-0000-0000-000000000201'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'test-alliance', 'Test Alliance', 'A test alliance', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values (:'categoryID', 'Conference', :'allianceID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategoryID', 'Technology', :'allianceID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'allianceID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- Event: has meeting to delete (with previous error)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    canceled,
    capacity,
    meeting_error,
    meeting_in_sync,
    meeting_provider_id,
    meeting_provider_host_user,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'eventID',
    :'groupID',
    'Event Test',
    'event-test',
    'Test event for meeting delete',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04',

    true,
    100,
    'Previous sync error',
    false,
    'zoom',
    'event-claim-host@example.com',
    true,
    current_timestamp
);

-- Meeting linked to event
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingEventID', :'eventID', 'zoom', '123456789', 'https://zoom.us/j/123456789', 'pass123');

-- Event with stale claim: has meeting to delete after owner state changes
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    canceled,
    capacity,
    meeting_error,
    meeting_in_sync,
    meeting_provider_id,
    meeting_provider_host_user,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'eventStaleClaimID',
    :'groupID',
    'Event Stale Claim',
    'event-stale-claim',
    'Test event for stale meeting delete',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-02 10:00:00-04',
    '2025-06-02 11:00:00-04',

    true,
    100,
    'Previous sync error',
    false,
    'zoom',
    'event-stale-claim-host@example.com',
    true,
    current_timestamp
);

-- Meeting linked to stale event claim
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingEventStaleClaimID', :'eventStaleClaimID', 'zoom', 'stale123', 'https://zoom.us/j/stale123', 'stale');

-- Event with reassigned claim: worker token no longer matches
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    canceled,
    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_provider_host_user,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'eventReassignedClaimID',
    :'groupID',
    'Event Reassigned Claim',
    'event-reassigned-claim',
    'Test event reclaimed by another worker',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-03 10:00:00-04',
    '2025-06-03 11:00:00-04',

    true,
    100,
    false,
    'zoom',
    'event-reassigned-claim-host@example.com',
    true,
    current_timestamp
);

-- Meeting linked to reassigned event claim
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingEventReassignedID', :'eventReassignedClaimID', 'zoom', 'reassigned123', 'https://zoom.us/j/reassigned123', 'pass');

-- Session: has meeting to delete (with previous error)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,

    meeting_error,
    meeting_in_sync,
    meeting_provider_id,
    meeting_provider_host_user,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionID',
    :'eventID',
    'Session Test',
    '2025-06-01 10:00:00-04',
    '2025-06-01 10:30:00-04',
    'virtual',

    'Previous sync error',
    false,
    'zoom',
    'session-claim-host@example.com',
    true,
    current_timestamp
);

-- Meeting linked to session
insert into meeting (meeting_id, session_id, meeting_provider_id, provider_meeting_id, join_url, password)
values (:'meetingSessionID', :'sessionID', 'zoom', '987654321', 'https://zoom.us/j/987654321', 'sesspass');

-- Orphan meeting (no event_id or session_id) claimed for deletion
insert into meeting (meeting_id, meeting_provider_id, provider_meeting_id, join_url, sync_claimed_at)
values (:'meetingOrphanID', 'zoom', '555666777', 'https://zoom.us/j/555666777', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete meeting record when linked to event
select lives_ok(
    format(
        'select delete_meeting(%L, %L, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid), get_event_meeting_sync_state_hash(%L::uuid))',
        :'meetingEventID',
        :'eventID',
        :'eventID',
        :'eventID'
    ),
    'Should delete meeting record when linked to event'
);
select is(
    (select count(*) from meeting where meeting_id = :'meetingEventID'),
    0::bigint,
    'Meeting record deleted for event'
);

-- Should mark event as synced and clear the claim after deleting meeting
select results_eq(
    format(
        $query$
        select
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from event
        where event_id = %L::uuid
        $query$,
        :'eventID'
    ),
    $expected$
    values (
        true,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Event marked as synced and claim cleared after deleting meeting'
);

-- Should not mark event as synced when delete completes after owner state changed
select lives_ok(
    format(
        $sql$
        with claimed as (
            select
                get_event_meeting_sync_state_hash(event_id) as sync_state_hash,
                meeting_sync_claimed_at
            from event
            where event_id = %L::uuid
        ),
        changed as (
            update event
            set name = 'Event Changed After Claim'
            where event_id = %L::uuid
            returning event_id
        )
        select delete_meeting(
            %L,
            %L,
            null,
            claimed.meeting_sync_claimed_at,
            claimed.sync_state_hash
        )
        from claimed, changed
        $sql$,
        :'eventStaleClaimID',
        :'eventStaleClaimID',
        :'meetingEventStaleClaimID',
        :'eventStaleClaimID'
    ),
    'Should delete meeting record for stale event claim'
);
select is(
    (select count(*) from meeting where meeting_id = :'meetingEventStaleClaimID'),
    0::bigint,
    'Meeting record deleted even when event claim is stale'
);
select results_eq(
    format(
        $query$
        select
            meeting_error,
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from event
        where event_id = %L::uuid
        $query$,
        :'eventStaleClaimID'
    ),
    $expected$
    values (
        'Previous sync error',
        false,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Event changed after delete claim remains out of sync'
);

-- Should not delete meeting when the worker no longer holds the claim
select lives_ok(
    format(
        'select delete_meeting(%L, %L, null, current_timestamp - interval ''1 hour'', get_event_meeting_sync_state_hash(%L::uuid))',
        :'meetingEventReassignedID',
        :'eventReassignedClaimID',
        :'eventReassignedClaimID'
    ),
    'Should accept delete_meeting with a mismatched claim token'
);
select is(
    (select count(*) from meeting where meeting_id = :'meetingEventReassignedID'),
    1::bigint,
    'Should keep meeting when claim token does not match'
);
select isnt(
    (select meeting_sync_claimed_at from event where event_id = :'eventReassignedClaimID'),
    null,
    'Should keep event claim when claim token does not match'
);

-- Should delete meeting record when linked to session
select lives_ok(
    format(
        'select delete_meeting(%L, null, %L, (select meeting_sync_claimed_at from session where session_id = %L::uuid), get_session_meeting_sync_state_hash(%L::uuid))',
        :'meetingSessionID',
        :'sessionID',
        :'sessionID',
        :'sessionID'
    ),
    'Should delete meeting record when linked to session'
);
select is(
    (select count(*) from meeting where meeting_id = :'meetingSessionID'),
    0::bigint,
    'Meeting record deleted for session'
);

-- Should mark session as synced and clear the claim after deleting meeting
select results_eq(
    format(
        $query$
        select
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from session
        where session_id = %L::uuid
        $query$,
        :'sessionID'
    ),
    $expected$
    values (
        true,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Session marked as synced and claim cleared after deleting meeting'
);

-- Should not delete orphan meeting when the claim token does not match
select lives_ok(
    format(
        'select delete_meeting(%L, null, null, current_timestamp - interval ''1 hour'', null)',
        :'meetingOrphanID'
    ),
    'Should accept orphan delete with a mismatched claim token'
);
select is(
    (select count(*) from meeting where meeting_id = :'meetingOrphanID'),
    1::bigint,
    'Should keep orphan meeting when claim token does not match'
);

-- Should delete orphan meeting record with a matching claim token
select lives_ok(
    format(
        'select delete_meeting(%L, null, null, (select sync_claimed_at from meeting where meeting_id = %L::uuid), null)',
        :'meetingOrphanID',
        :'meetingOrphanID'
    ),
    'Should delete orphan meeting record'
);
select is(
    (select count(*) from meeting where meeting_id = :'meetingOrphanID'),
    0::bigint,
    'Orphan meeting record deleted'
);

-- Should clear previous error when deleting meeting linked to event
select is(
    (select meeting_error from event where event_id = :'eventID'),
    null,
    'Event meeting_error cleared after successful delete_meeting'
);

-- Should clear previous error when deleting meeting linked to session
select is(
    (select meeting_error from session where session_id = :'sessionID'),
    null,
    'Session meeting_error cleared after successful delete_meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
