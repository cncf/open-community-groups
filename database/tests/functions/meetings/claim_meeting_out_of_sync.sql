-- Tests claiming event, session and orphan meetings that need provider synchronization.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a050000-0000-0000-0000-000000000001'
\set eventCanceledDeleteID '7a050000-0000-0000-0000-000000000002'
\set eventCanceledNoMeetingID '7a050000-0000-0000-0000-000000000003'
\set eventCategoryID '7a050000-0000-0000-0000-000000000004'
\set eventCreateID '7a050000-0000-0000-0000-000000000005'
\set eventDisabledID '7a050000-0000-0000-0000-000000000007'
\set eventInSyncID '7a050000-0000-0000-0000-000000000008'
\set eventNoRequestID '7a050000-0000-0000-0000-000000000009'
\set eventPastImportID '7a050000-0000-0000-0000-000000000011'
\set eventUnpublishedID '7a050000-0000-0000-0000-000000000012'
\set eventUnpublishedWithMeetingID '7a050000-0000-0000-0000-000000000013'
\set eventUpdateID '7a050000-0000-0000-0000-000000000014'
\set eventWithSessionsID '7a050000-0000-0000-0000-000000000015'
\set groupCategoryID '7a050000-0000-0000-0000-000000000016'
\set groupID '7a050000-0000-0000-0000-000000000017'
\set meetingDisabledID '7a050000-0000-0000-0000-000000000018'
\set meetingEventCanceledDeleteID '7a050000-0000-0000-0000-000000000019'
\set meetingEventOrphanDetachedID '7a050000-0000-0000-0000-000000000021'
\set meetingEventUnpublishedID '7a050000-0000-0000-0000-000000000022'
\set meetingEventUpdateID '7a050000-0000-0000-0000-000000000023'
\set meetingOrphanID '7a050000-0000-0000-0000-000000000024'
\set meetingSessionDeleteID '7a050000-0000-0000-0000-000000000026'
\set meetingSessionDisabledID '7a050000-0000-0000-0000-000000000027'
\set meetingSessionOrphanDetachedID '7a050000-0000-0000-0000-000000000028'
\set meetingSessionUnpublishedID '7a050000-0000-0000-0000-000000000029'
\set meetingSessionUpdateID '7a050000-0000-0000-0000-000000000030'
\set sessionCanceledNoMeetingID '7a050000-0000-0000-0000-000000000031'
\set sessionCreateID '7a050000-0000-0000-0000-000000000032'
\set sessionDeleteID '7a050000-0000-0000-0000-000000000034'
\set sessionDisabledID '7a050000-0000-0000-0000-000000000035'
\set sessionPastImportID '7a050000-0000-0000-0000-000000000037'
\set sessionUnpublishedNoMeetingID '7a050000-0000-0000-0000-000000000038'
\set sessionUnpublishedWithMeetingID '7a050000-0000-0000-0000-000000000039'
\set sessionUpdateID '7a050000-0000-0000-0000-000000000040'
\set userEventHostID '7a050000-0000-0000-0000-000000000041'
\set userEventSpeakerID '7a050000-0000-0000-0000-000000000042'
\set userSessionSpeakerID '7a050000-0000-0000-0000-000000000043'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users for event_host, event_speaker, and session_speaker host aggregation
select fx_user(:'userEventHostID', jsonb_build_object(
    'email', 'eventhost@example.com',
    'username', 'eventhost'
));
select fx_user(:'userEventSpeakerID', jsonb_build_object(
    'email', 'eventspeaker@example.com',
    'username', 'eventspeaker'
));
select fx_user(:'userSessionSpeakerID', jsonb_build_object(
    'email', 'sessionspeaker@example.com',
    'username', 'sessionspeaker'
));

-- Published event needing create, with a reserved host and a previous error
select fx_event(:'eventCreateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'meeting_error', 'previous event create error',
    'meeting_hosts', array['explicit@example.com'],
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'claim-event-create-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Event Create Test',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event needing update of its existing meeting
select fx_event(:'eventUpdateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '2 days 2 hours',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Event Update Test',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Published in-sync parent of the session create, update and disabled rows
select fx_event(:'eventWithSessionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '3 days 2 hours',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp + interval '3 days'
));

-- Canceled event needing delete of its meeting
select fx_event(:'eventCanceledDeleteID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', current_timestamp + interval '4 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '4 days'
));

-- Unpublished event needing delete without a meeting row
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '5 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '5 days'
));

-- Unpublished event needing delete of its meeting (a deleted event is always
-- unpublished, so it takes this same path)
select fx_event(:'eventUnpublishedWithMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '5 days 2 hours',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '5 days 1 hour'
));

-- Published event whose meeting was disabled
select fx_event(:'eventDisabledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '6 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_requested', false,
    'published', true,
    'starts_at', current_timestamp + interval '6 days'
));

-- Canceled event needing delete before its meeting was created
select fx_event(:'eventCanceledNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', current_timestamp + interval '7 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '7 days'
));

-- Published event already in sync
select fx_event(:'eventInSyncID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '8 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp + interval '8 days'
));

-- Published event in sync without a meeting request
select fx_event(:'eventNoRequestID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '9 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_requested', false,
    'published', true,
    'starts_at', current_timestamp + interval '9 days'
));

-- Imported past event that is eligible except for its historical start
select fx_event(:'eventPastImportID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2020-06-11 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', '2020-06-11 10:00:00+00'
));

-- Event host included in the event and session meeting claim payloads
insert into event_host (event_id, user_id)
values (:'eventCreateID', :'userEventHostID');

-- Parent event host included in the session meeting claim payloads
insert into event_host (event_id, user_id)
values (:'eventWithSessionsID', :'userEventHostID');

-- Event speaker included in the event meeting claim payload
insert into event_speaker (event_id, user_id, featured)
values (:'eventCreateID', :'userEventSpeakerID', false);

-- Session needing create on a published event
insert into session (
    ends_at,
    event_id,
    meeting_hosts,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    current_timestamp + interval '3 days 30 minutes',
    :'eventWithSessionsID',
    array['sessionhost@example.com'],
    false,
    'zoom',
    true,
    'Session Create Test',
    :'sessionCreateID',
    'virtual',
    current_timestamp + interval '3 days'
);

-- Session needing update, with a reserved host and a previous error
insert into session (
    ends_at,
    event_id,
    meeting_error,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    current_timestamp + interval '3 days 1 hour 30 minutes',
    :'eventWithSessionsID',
    'previous session update error',
    false,
    'claim-session-update-host@example.com',
    'zoom',
    true,
    'Session Update Test',
    :'sessionUpdateID',
    'virtual',
    current_timestamp + interval '3 days 1 hour'
);

-- Session whose meeting was disabled on a published event
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
    current_timestamp + interval '3 days 2 hours',
    :'eventWithSessionsID',
    false,
    false,
    'Session Disabled Test',
    :'sessionDisabledID',
    'virtual',
    current_timestamp + interval '3 days 1 hour 30 minutes'
);

-- Session needing delete because its parent event was canceled
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
    current_timestamp + interval '4 days 30 minutes',
    :'eventCanceledDeleteID',
    false,
    'zoom',
    true,
    'Session Delete Test',
    :'sessionDeleteID',
    'virtual',
    current_timestamp + interval '4 days'
);

-- Session needing delete on an unpublished event without a meeting row
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
    current_timestamp + interval '5 days 30 minutes',
    :'eventUnpublishedID',
    false,
    'zoom',
    true,
    'Session Unpublished No Meeting Test',
    :'sessionUnpublishedNoMeetingID',
    'virtual',
    current_timestamp + interval '5 days'
);

-- Session needing delete of its meeting on an unpublished event
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
    current_timestamp + interval '5 days 1 hour',
    :'eventUnpublishedID',
    false,
    'zoom',
    true,
    'Session Unpublished With Meeting Test',
    :'sessionUnpublishedWithMeetingID',
    'virtual',
    current_timestamp + interval '5 days 30 minutes'
);

-- Session needing delete on a canceled event before its meeting was created
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
    current_timestamp + interval '7 days 30 minutes',
    :'eventCanceledNoMeetingID',
    false,
    'zoom',
    true,
    'Session Canceled No Meeting Test',
    :'sessionCanceledNoMeetingID',
    'virtual',
    current_timestamp + interval '7 days'
);

-- Imported past session that is eligible except for its historical start
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
    '2020-06-11 10:30:00+00',
    :'eventPastImportID',
    false,
    'zoom',
    true,
    'Past Import Session Test',
    :'sessionPastImportID',
    'virtual',
    '2020-06-11 10:00:00+00'
);

-- Existing event meeting rows
insert into meeting (
    event_id,
    join_url,
    meeting_id,
    meeting_provider_id,
    password,
    provider_meeting_id
) values
(
    :'eventUpdateID',
    'https://zoom.us/j/event-update',
    :'meetingEventUpdateID',
    'zoom',
    'eventpass',
    'event-update'
),
(
    :'eventCanceledDeleteID',
    'https://zoom.us/j/event-canceled-delete',
    :'meetingEventCanceledDeleteID',
    'zoom',
    null,
    'event-canceled-delete'
),
(
    :'eventDisabledID',
    'https://zoom.us/j/event-disabled',
    :'meetingDisabledID',
    'zoom',
    null,
    'event-disabled'
),
(
    :'eventUnpublishedWithMeetingID',
    'https://zoom.us/j/event-unpublished',
    :'meetingEventUnpublishedID',
    'zoom',
    null,
    'event-unpublished'
);

-- Existing session meeting rows
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    password,
    provider_meeting_id,
    session_id
) values
(
    'https://zoom.us/j/session-update',
    :'meetingSessionUpdateID',
    'zoom',
    'sessionpass',
    'session-update',
    :'sessionUpdateID'
),
(
    'https://zoom.us/j/session-delete',
    :'meetingSessionDeleteID',
    'zoom',
    null,
    'session-delete',
    :'sessionDeleteID'
),
(
    'https://zoom.us/j/session-disabled',
    :'meetingSessionDisabledID',
    'zoom',
    null,
    'session-disabled',
    :'sessionDisabledID'
),
(
    'https://zoom.us/j/session-unpublished',
    :'meetingSessionUnpublishedID',
    'zoom',
    null,
    'session-unpublished',
    :'sessionUnpublishedWithMeetingID'
);

-- Orphan meeting with the provider host user that created it
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_host_user_id,
    provider_meeting_id
) values (
    'https://zoom.us/j/orphan',
    :'meetingOrphanID',
    'zoom',
    'orphan-host-user',
    'orphan'
);

-- Further detached orphan meetings claimed in the same batch
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values
(
    'https://zoom.us/j/event-orphan-detached',
    :'meetingEventOrphanDetachedID',
    'zoom',
    'event-orphan-detached'
),
(
    'https://zoom.us/j/session-orphan-detached',
    :'meetingSessionOrphanDetachedID',
    'zoom',
    'session-orphan-detached'
);

-- Session speaker included in the session meeting claim payload
insert into session_speaker (session_id, user_id, featured)
values (:'sessionCreateID', :'userSessionSpeakerID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Claim every eligible owner and orphan meeting (2 event and 2 session
-- create/update, 5 event and 5 session delete, 3 orphan), keyed by the
-- session, event or orphan meeting id; claim order is covered by
-- claim_meeting_out_of_sync_priority.sql
with claims as materialized (
    select claim_meeting_out_of_sync() as claim
    from generate_series(1, 17)
)
select jsonb_object_agg(
    coalesce(claim->>'session_id', claim->>'event_id', claim->>'meeting_id'),
    claim
) filter (where claim is not null) as "claims"
from claims \gset

-- Should return an event needing create with combined hosts and its reserved host
select is(
    :'claims'::jsonb -> :'eventCreateID',
    format(
        $json${
            "delete": false,
            "duration_secs": 3600,
            "event_id": "%s",
            "hosts": ["eventhost@example.com", "eventspeaker@example.com", "explicit@example.com"],
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "provider_host_user_id": "claim-event-create-host@example.com",
            "timezone": "UTC",
            "topic": "Event Create Test"
        }$json$,
        :'eventCreateID'
    )::jsonb || jsonb_build_object(
        'starts_at', current_timestamp + interval '1 day',
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventCreateID')
    ),
    'Should return an event needing create with combined hosts and its reserved host'
);

-- Should claim the event, clear its error and keep it out of sync
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'eventCreateID'
    ),
    $$ values (null::text, false, 'claim-event-create-host@example.com', current_timestamp) $$,
    'Should claim the event, clear its error and keep it out of sync'
);

-- Should return an event needing update with its existing provider fields
select is(
    :'claims'::jsonb -> :'eventUpdateID',
    format(
        $json${
            "delete": false,
            "duration_secs": 7200,
            "event_id": "%s",
            "join_url": "https://zoom.us/j/event-update",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "password": "eventpass",
            "provider_meeting_id": "event-update",
            "timezone": "UTC",
            "topic": "Event Update Test"
        }$json$,
        :'eventUpdateID',
        :'meetingEventUpdateID'
    )::jsonb || jsonb_build_object(
        'starts_at', current_timestamp + interval '2 days',
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventUpdateID')
    ),
    'Should return an event needing update with its existing provider fields'
);

-- Should return a session needing create with combined hosts
select is(
    :'claims'::jsonb -> :'sessionCreateID',
    format(
        $json${
            "delete": false,
            "duration_secs": 1800,
            "hosts": ["eventhost@example.com", "sessionhost@example.com", "sessionspeaker@example.com"],
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "session_id": "%s",
            "timezone": "UTC",
            "topic": "Session Create Test"
        }$json$,
        :'sessionCreateID'
    )::jsonb || jsonb_build_object(
        'starts_at', current_timestamp + interval '3 days',
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionCreateID')
    ),
    'Should return a session needing create with combined hosts'
);

-- Should return a session needing update with its existing provider fields and reserved host
select is(
    :'claims'::jsonb -> :'sessionUpdateID',
    format(
        $json${
            "delete": false,
            "duration_secs": 1800,
            "hosts": ["eventhost@example.com"],
            "join_url": "https://zoom.us/j/session-update",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "password": "sessionpass",
            "provider_host_user_id": "claim-session-update-host@example.com",
            "provider_meeting_id": "session-update",
            "session_id": "%s",
            "timezone": "UTC",
            "topic": "Session Update Test"
        }$json$,
        :'meetingSessionUpdateID',
        :'sessionUpdateID'
    )::jsonb || jsonb_build_object(
        'starts_at', current_timestamp + interval '3 days 1 hour',
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionUpdateID')
    ),
    'Should return a session needing update with its existing provider fields and reserved host'
);

-- Should claim the session, clear its error and keep it out of sync
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from session where session_id = %L $$,
        :'sessionUpdateID'
    ),
    $$ values (null::text, false, 'claim-session-update-host@example.com', current_timestamp) $$,
    'Should claim the session, clear its error and keep it out of sync'
);

-- Should return a canceled event with a meeting for delete
select is(
    :'claims'::jsonb -> :'eventCanceledDeleteID',
    format(
        $json${
            "delete": true,
            "event_id": "%s",
            "join_url": "https://zoom.us/j/event-canceled-delete",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_meeting_id": "event-canceled-delete"
        }$json$,
        :'eventCanceledDeleteID',
        :'meetingEventCanceledDeleteID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventCanceledDeleteID')
    ),
    'Should return a canceled event with a meeting for delete'
);

-- Should return an unpublished event without a meeting for delete
select is(
    :'claims'::jsonb -> :'eventUnpublishedID',
    format(
        $json${
            "delete": true,
            "event_id": "%s"
        }$json$,
        :'eventUnpublishedID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventUnpublishedID')
    ),
    'Should return an unpublished event without a meeting for delete'
);

-- Should return an unpublished event with a meeting for delete
select is(
    :'claims'::jsonb -> :'eventUnpublishedWithMeetingID',
    format(
        $json${
            "delete": true,
            "event_id": "%s",
            "join_url": "https://zoom.us/j/event-unpublished",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_meeting_id": "event-unpublished"
        }$json$,
        :'eventUnpublishedWithMeetingID',
        :'meetingEventUnpublishedID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventUnpublishedWithMeetingID')
    ),
    'Should return an unpublished event with a meeting for delete'
);

-- Should return an event whose meeting was disabled for delete
select is(
    :'claims'::jsonb -> :'eventDisabledID',
    format(
        $json${
            "delete": true,
            "event_id": "%s",
            "join_url": "https://zoom.us/j/event-disabled",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_meeting_id": "event-disabled"
        }$json$,
        :'eventDisabledID',
        :'meetingDisabledID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventDisabledID')
    ),
    'Should return an event whose meeting was disabled for delete'
);

-- Should return an event canceled before meeting creation for delete without meeting fields
select is(
    :'claims'::jsonb -> :'eventCanceledNoMeetingID',
    format(
        $json${
            "delete": true,
            "event_id": "%s"
        }$json$,
        :'eventCanceledNoMeetingID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventCanceledNoMeetingID')
    ),
    'Should return an event canceled before meeting creation for delete without meeting fields'
);

-- Should return a session on a canceled event with a meeting for delete
select is(
    :'claims'::jsonb -> :'sessionDeleteID',
    format(
        $json${
            "delete": true,
            "join_url": "https://zoom.us/j/session-delete",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_meeting_id": "session-delete",
            "session_id": "%s"
        }$json$,
        :'meetingSessionDeleteID',
        :'sessionDeleteID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionDeleteID')
    ),
    'Should return a session on a canceled event with a meeting for delete'
);

-- Should return a session on a canceled event before meeting creation for delete without meeting fields
select is(
    :'claims'::jsonb -> :'sessionCanceledNoMeetingID',
    format(
        $json${
            "delete": true,
            "session_id": "%s"
        }$json$,
        :'sessionCanceledNoMeetingID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionCanceledNoMeetingID')
    ),
    'Should return a session on a canceled event before meeting creation for delete without meeting fields'
);

-- Should return a session on an unpublished event without a meeting for delete
select is(
    :'claims'::jsonb -> :'sessionUnpublishedNoMeetingID',
    format(
        $json${
            "delete": true,
            "session_id": "%s"
        }$json$,
        :'sessionUnpublishedNoMeetingID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionUnpublishedNoMeetingID')
    ),
    'Should return a session on an unpublished event without a meeting for delete'
);

-- Should return a session on an unpublished event with a meeting for delete
select is(
    :'claims'::jsonb -> :'sessionUnpublishedWithMeetingID',
    format(
        $json${
            "delete": true,
            "join_url": "https://zoom.us/j/session-unpublished",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_meeting_id": "session-unpublished",
            "session_id": "%s"
        }$json$,
        :'meetingSessionUnpublishedID',
        :'sessionUnpublishedWithMeetingID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionUnpublishedWithMeetingID')
    ),
    'Should return a session on an unpublished event with a meeting for delete'
);

-- Should return a session whose meeting was disabled for delete
select is(
    :'claims'::jsonb -> :'sessionDisabledID',
    format(
        $json${
            "delete": true,
            "join_url": "https://zoom.us/j/session-disabled",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_meeting_id": "session-disabled",
            "session_id": "%s"
        }$json$,
        :'meetingSessionDisabledID',
        :'sessionDisabledID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionDisabledID')
    ),
    'Should return a session whose meeting was disabled for delete'
);

-- Should return an orphan meeting for delete with its provider host user
select is(
    :'claims'::jsonb -> :'meetingOrphanID',
    format(
        $json${
            "delete": true,
            "join_url": "https://zoom.us/j/orphan",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "provider_host_user_id": "orphan-host-user",
            "provider_meeting_id": "orphan"
        }$json$,
        :'meetingOrphanID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', current_timestamp
    ),
    'Should return an orphan meeting for delete with its provider host user'
);

-- Should claim the orphan meeting on the meeting row
select results_eq(
    format(
        $$ select sync_claimed_at, updated_at from meeting where meeting_id = %L $$,
        :'meetingOrphanID'
    ),
    $$ values (current_timestamp, current_timestamp) $$,
    'Should claim the orphan meeting on the meeting row'
);

-- Should claim every detached orphan meeting
select set_eq(
    format(
        $$
        select (claim->>'meeting_id')::uuid
        from jsonb_each(%L::jsonb) as claims(key, claim)
        where not claim ? 'event_id'
          and not claim ? 'session_id'
        $$,
        :'claims'
    ),
    format(
        $$ values (%L::uuid), (%L::uuid), (%L::uuid) $$,
        :'meetingEventOrphanDetachedID',
        :'meetingOrphanID',
        :'meetingSessionOrphanDetachedID'
    ),
    'Should claim every detached orphan meeting'
);

-- Should not claim imported past events and sessions for provider create or update
select results_eq(
    format(
        $$
        select meeting_sync_claimed_at from event where event_id = %L
        union all
        select meeting_sync_claimed_at from session where session_id = %L
        $$,
        :'eventPastImportID',
        :'sessionPastImportID'
    ),
    $$ values (null::timestamptz), (null::timestamptz) $$,
    'Should not claim imported past events and sessions for provider create or update'
);

-- Should return null once claimed, in-sync and no-request rows are all that remain
select is(
    claim_meeting_out_of_sync(),
    null::jsonb,
    'Should return null once claimed, in-sync and no-request rows are all that remain'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
