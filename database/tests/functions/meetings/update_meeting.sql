-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a0f0000-0000-0000-0000-000000000001'
\set eventCategoryID '7a0f0000-0000-0000-0000-000000000002'
\set eventID '7a0f0000-0000-0000-0000-000000000003'
\set eventReassignedClaimID '7a0f0000-0000-0000-0000-000000000004'
\set eventStaleClaimID '7a0f0000-0000-0000-0000-000000000005'
\set groupCategoryID '7a0f0000-0000-0000-0000-000000000006'
\set groupID '7a0f0000-0000-0000-0000-000000000007'
\set meetingEventID '7a0f0000-0000-0000-0000-000000000008'
\set meetingEventReassignedID '7a0f0000-0000-0000-0000-000000000009'
\set meetingEventStaleClaimID '7a0f0000-0000-0000-0000-000000000010'
\set meetingSessionID '7a0f0000-0000-0000-0000-000000000011'
\set sessionID '7a0f0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event: has meeting to update (with previous error)
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-01 11:00:00-04',
    'event_kind_id', 'virtual',
    'meeting_error', 'Previous sync error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'event-claim-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp,
    'starts_at', '2025-06-01 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Meeting linked to event
insert into meeting (
    meeting_id,
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id
) values (
    :'meetingEventID',
    :'eventID',
    'https://zoom.us/j/123456789-update-meeting',
    'zoom',
    'pass123',
    '123456789-update-meeting'
);

-- Event with stale claim: has meeting to update after owner state changes
select fx_event(:'eventStaleClaimID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-02 11:00:00-04',
    'event_kind_id', 'virtual',
    'meeting_error', 'Previous sync error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'event-stale-claim-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp,
    'starts_at', '2025-06-02 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Meeting linked to stale event claim
insert into meeting (
    meeting_id,
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id
) values (
    :'meetingEventStaleClaimID',
    :'eventStaleClaimID',
    'https://zoom.us/j/stale123-update-meeting',
    'zoom',
    'stale',
    'stale123-update-meeting'
);

-- Event with reassigned claim: worker token no longer matches
select fx_event(:'eventReassignedClaimID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-03 11:00:00-04',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'event-reassigned-claim-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp,
    'starts_at', '2025-06-03 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Meeting linked to reassigned event claim
insert into meeting (
    meeting_id,
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id
) values (
    :'meetingEventReassignedID',
    :'eventReassignedClaimID',
    'https://zoom.us/j/reassigned123-update-meeting',
    'zoom',
    'pass',
    'reassigned123-update-meeting'
);

-- Session: has meeting to update (with previous error)
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
insert into meeting (
    meeting_id,
    session_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id
) values (
    :'meetingSessionID',
    :'sessionID',
    'https://zoom.us/j/987654321-update-meeting',
    'zoom',
    'sesspass',
    '987654321-update-meeting'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update meeting record when linked to event
select lives_ok(
    format(
        'select update_meeting(%L, ''111222333'', ''https://zoom.us/j/111222333'', ''newpass'', %L, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid), get_event_meeting_sync_state_hash(%L::uuid))',
        :'meetingEventID',
        :'eventID',
        :'eventID',
        :'eventID'
    ),
    'Should update meeting record when linked to event'
);
select is(
    (select provider_meeting_id from meeting where meeting_id = :'meetingEventID'),
    '111222333',
    'Meeting record updated for event'
);

-- Should mark event as synced and clear the claim after updating meeting
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
    'Event marked as synced and claim cleared after updating meeting'
);

-- Should not mark event as synced when update completes after owner state changed
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
        select update_meeting(
            %L,
            'stale456',
            'https://zoom.us/j/stale456',
            'stale-new',
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
    'Should update meeting record for stale event claim'
);
select is(
    (select provider_meeting_id from meeting where meeting_id = :'meetingEventStaleClaimID'),
    'stale456',
    'Meeting record updated even when event claim is stale'
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
    'Event changed after update claim remains out of sync'
);

-- Should not update meeting when the worker no longer holds the claim
select lives_ok(
    format(
        'select update_meeting(%L, ''reassigned456'', ''https://zoom.us/j/reassigned456'', ''newpass'', %L, null, current_timestamp - interval ''1 hour'', get_event_meeting_sync_state_hash(%L::uuid))',
        :'meetingEventReassignedID',
        :'eventReassignedClaimID',
        :'eventReassignedClaimID'
    ),
    'Should accept update_meeting with a mismatched claim token'
);
select is(
    (select provider_meeting_id from meeting where meeting_id = :'meetingEventReassignedID'),
    'reassigned123-update-meeting',
    'Should keep meeting unchanged when claim token does not match'
);
select isnt(
    (select meeting_sync_claimed_at from event where event_id = :'eventReassignedClaimID'),
    null,
    'Should keep event claim when claim token does not match'
);

-- Mark event as out of sync again for next test
update event set meeting_in_sync = false where event_id = :'eventID';

-- Should update meeting record when linked to session
select lives_ok(
    format(
        'select update_meeting(%L, ''444555666'', ''https://zoom.us/j/444555666'', ''newsesspass'', null, %L, (select meeting_sync_claimed_at from session where session_id = %L::uuid), get_session_meeting_sync_state_hash(%L::uuid))',
        :'meetingSessionID',
        :'sessionID',
        :'sessionID',
        :'sessionID'
    ),
    'Should update meeting record when linked to session'
);
select is(
    (select provider_meeting_id from meeting where meeting_id = :'meetingSessionID'),
    '444555666',
    'Meeting record updated for session'
);

-- Should mark session as synced and clear the claim after updating meeting
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
    'Session marked as synced and claim cleared after updating meeting'
);

-- Should clear previous error when updating meeting linked to event
select is(
    (select meeting_error from event where event_id = :'eventID'),
    null,
    'Event meeting_error cleared after successful update_meeting'
);

-- Should clear previous error when updating meeting linked to session
select is(
    (select meeting_error from session where session_id = :'sessionID'),
    null,
    'Session meeting_error cleared after successful update_meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
