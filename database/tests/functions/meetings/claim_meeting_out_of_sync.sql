-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(26);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a050000-0000-0000-0000-000000000001'
\set eventCanceledDeleteID '7a050000-0000-0000-0000-000000000002'
\set eventCanceledNoMeetingID '7a050000-0000-0000-0000-000000000003'
\set eventCategoryID '7a050000-0000-0000-0000-000000000004'
\set eventCreateID '7a050000-0000-0000-0000-000000000005'
\set eventDeletedID '7a050000-0000-0000-0000-000000000006'
\set eventDisabledID '7a050000-0000-0000-0000-000000000007'
\set eventInSyncID '7a050000-0000-0000-0000-000000000008'
\set eventNoRequestID '7a050000-0000-0000-0000-000000000009'
\set eventOrphanCascadeID '7a050000-0000-0000-0000-000000000010'
\set eventPastImportID '7a050000-0000-0000-0000-000000000011'
\set eventUnpublishedID '7a050000-0000-0000-0000-000000000012'
\set eventUnpublishedWithMeetingID '7a050000-0000-0000-0000-000000000013'
\set eventUpdateID '7a050000-0000-0000-0000-000000000014'
\set eventWithSessionsID '7a050000-0000-0000-0000-000000000015'
\set groupCategoryID '7a050000-0000-0000-0000-000000000016'
\set groupID '7a050000-0000-0000-0000-000000000017'
\set meetingDisabledID '7a050000-0000-0000-0000-000000000018'
\set meetingEventCanceledDeleteID '7a050000-0000-0000-0000-000000000019'
\set meetingEventDeletedID '7a050000-0000-0000-0000-000000000020'
\set meetingEventOrphanCascadeID '7a050000-0000-0000-0000-000000000021'
\set meetingEventUnpublishedID '7a050000-0000-0000-0000-000000000022'
\set meetingEventUpdateID '7a050000-0000-0000-0000-000000000023'
\set meetingOrphanID '7a050000-0000-0000-0000-000000000024'
\set meetingSessionDeletedParentID '7a050000-0000-0000-0000-000000000025'
\set meetingSessionDeleteID '7a050000-0000-0000-0000-000000000026'
\set meetingSessionDisabledID '7a050000-0000-0000-0000-000000000027'
\set meetingSessionOrphanCascadeID '7a050000-0000-0000-0000-000000000028'
\set meetingSessionUnpublishedID '7a050000-0000-0000-0000-000000000029'
\set meetingSessionUpdateID '7a050000-0000-0000-0000-000000000030'
\set sessionCanceledNoMeetingID '7a050000-0000-0000-0000-000000000031'
\set sessionCreateID '7a050000-0000-0000-0000-000000000032'
\set sessionDeletedParentID '7a050000-0000-0000-0000-000000000033'
\set sessionDeleteID '7a050000-0000-0000-0000-000000000034'
\set sessionDisabledID '7a050000-0000-0000-0000-000000000035'
\set sessionOrphanCascadeID '7a050000-0000-0000-0000-000000000036'
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

-- Event candidates and exclusions
-- Delete-focused rows that could interfere start in sync and are reopened later
select fx_event(:'eventCreateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'meeting_hosts', array['explicit@example.com'],
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Event Create Test',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
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
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'deleted', true,
    'ends_at', current_timestamp + interval '4 days 2 hours',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '4 days 1 hour'
));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '5 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'name', 'Event Unpublished Test',
    'starts_at', current_timestamp + interval '5 days'
));
select fx_event(:'eventUnpublishedWithMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '5 days 2 hours',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '5 days 1 hour'
));
select fx_event(:'eventDisabledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '6 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_requested', false,
    'published', true,
    'starts_at', current_timestamp + interval '6 days'
));
select fx_event(:'eventCanceledNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', current_timestamp + interval '7 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '7 days'
));
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
select fx_event(:'eventNoRequestID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '9 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_requested', false,
    'published', true,
    'starts_at', current_timestamp + interval '9 days'
));
select fx_event(:'eventPastImportID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2020-06-11 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', '2020-06-11 10:00:00+00'
));
select fx_event(:'eventOrphanCascadeID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '10 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp + interval '10 days'
));

-- Session candidates
-- Delete-focused rows start in sync so event and session create/update priority is stable
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
) values
(
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
),
(
    current_timestamp + interval '3 days 1 hour 30 minutes',
    :'eventWithSessionsID',
    null,
    false,
    'zoom',
    true,
    'Session Update Test',
    :'sessionUpdateID',
    'virtual',
    current_timestamp + interval '3 days 1 hour'
),
(
    current_timestamp + interval '4 days 30 minutes',
    :'eventCanceledDeleteID',
    null,
    true,
    'zoom',
    true,
    'Session Delete Test',
    :'sessionDeleteID',
    'virtual',
    current_timestamp + interval '4 days'
),
(
    current_timestamp + interval '4 days 1 hour 30 minutes',
    :'eventDeletedID',
    null,
    true,
    'zoom',
    true,
    'Session Deleted Parent Test',
    :'sessionDeletedParentID',
    'virtual',
    current_timestamp + interval '4 days 1 hour'
),
(
    current_timestamp + interval '7 days 30 minutes',
    :'eventCanceledNoMeetingID',
    null,
    true,
    'zoom',
    true,
    'Session Canceled No Meeting Test',
    :'sessionCanceledNoMeetingID',
    'virtual',
    current_timestamp + interval '7 days'
),
(
    current_timestamp + interval '5 days 30 minutes',
    :'eventUnpublishedID',
    null,
    true,
    'zoom',
    true,
    'Session Unpublished No Meeting Test',
    :'sessionUnpublishedNoMeetingID',
    'virtual',
    current_timestamp + interval '5 days'
),
(
    current_timestamp + interval '5 days 1 hour',
    :'eventUnpublishedID',
    null,
    true,
    'zoom',
    true,
    'Session Unpublished With Meeting Test',
    :'sessionUnpublishedWithMeetingID',
    'virtual',
    current_timestamp + interval '5 days 30 minutes'
),
(
    current_timestamp + interval '3 days 2 hours',
    :'eventWithSessionsID',
    null,
    true,
    null,
    false,
    'Session Disabled Test',
    :'sessionDisabledID',
    'virtual',
    current_timestamp + interval '3 days 1 hour 30 minutes'
),
(
    current_timestamp + interval '10 days 30 minutes',
    :'eventOrphanCascadeID',
    null,
    true,
    'zoom',
    true,
    'Session Orphan Cascade Test',
    :'sessionOrphanCascadeID',
    'virtual',
    current_timestamp + interval '10 days'
),
(
    '2020-06-11 10:30:00+00',
    :'eventPastImportID',
    null,
    true,
    'zoom',
    true,
    'Past Import Session Test',
    :'sessionPastImportID',
    'virtual',
    '2020-06-11 10:00:00+00'
);

-- Hosts and speakers for combined hosts testing
-- eventCreateID combines explicit meeting_hosts, event_host, and event_speaker
insert into event_host (event_id, user_id)
values (:'eventCreateID', :'userEventHostID');

-- Event speaker included in the event meeting claim payload
insert into event_speaker (event_id, user_id, featured)
values (:'eventCreateID', :'userEventSpeakerID', false);

-- eventWithSessionsID and sessionCreateID combine parent host and session speaker
insert into event_host (event_id, user_id)
values (:'eventWithSessionsID', :'userEventHostID');

-- Session speaker included in the session meeting claim payload
insert into session_speaker (session_id, user_id, featured)
values (:'sessionCreateID', :'userSessionSpeakerID', false);

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
    :'eventDeletedID',
    'https://zoom.us/j/event-deleted',
    :'meetingEventDeletedID',
    'zoom',
    null,
    'event-deleted'
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
    :'eventOrphanCascadeID',
    'https://zoom.us/j/event-orphan-cascade',
    :'meetingEventOrphanCascadeID',
    'zoom',
    null,
    'event-orphan-cascade'
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
    'https://zoom.us/j/session-deleted-parent',
    :'meetingSessionDeletedParentID',
    'zoom',
    null,
    'session-deleted-parent',
    :'sessionDeletedParentID'
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
    'https://zoom.us/j/session-orphan-cascade',
    :'meetingSessionOrphanCascadeID',
    'zoom',
    null,
    'session-orphan-cascade',
    :'sessionOrphanCascadeID'
),
(
    'https://zoom.us/j/session-unpublished',
    :'meetingSessionUnpublishedID',
    'zoom',
    null,
    'session-unpublished',
    :'sessionUnpublishedWithMeetingID'
);

-- Existing orphan meeting row
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    'https://zoom.us/j/orphan',
    :'meetingOrphanID',
    'zoom',
    'orphan'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Event create - returns event with delete=false and no meeting row
-- Priority: event create/update work is claimed before delete work
-- Hosts include explicit meeting_hosts, event_host, and event_speaker emails
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": false,
        "duration_secs": 3600,
        "event_id": "%s",
        "hosts": ["eventhost@example.com", "eventspeaker@example.com", "explicit@example.com"],
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "timezone": "UTC",
        "topic": "Event Create Test"
    }$json$,
        :'eventCreateID'
    )::jsonb,
    'Event needing create returns correctly'
);
select isnt(
    (select meeting_sync_claimed_at from event where event_id = :'eventCreateID'),
    null,
    'Should claim selected event create'
);

-- Mark claimed event as synced to advance to the next queue item
update event set meeting_in_sync = true where event_id = :'eventCreateID';

-- Event update - returns event with delete=false and existing provider fields
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Event needing update returns correctly'
);

-- Mark claimed event as synced to advance to the next queue item
update event set meeting_in_sync = true where event_id = :'eventUpdateID';

-- Session create - returns session with delete=false and no meeting row
-- Priority: session create/update work is claimed before delete work
-- Hosts include explicit meeting_hosts, parent event_host, and session_speaker emails
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Session needing create returns correctly'
);

-- Mark claimed session as synced to advance to the next queue item
update session set meeting_in_sync = true where session_id = :'sessionCreateID';

-- Session update - returns session with delete=false and existing provider fields
-- Hosts include parent event_host emails only
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
        "provider_meeting_id": "session-update",
        "session_id": "%s",
        "timezone": "UTC",
        "topic": "Session Update Test"
    }$json$,
        :'meetingSessionUpdateID',
        :'sessionUpdateID'
    )::jsonb,
    'Session needing update returns correctly'
);

-- Mark claimed session as synced to advance to the next queue item
update session set meeting_in_sync = true where session_id = :'sessionUpdateID';

-- Event delete - returns canceled event with delete=true
-- Priority: delete operations come after event and session create/update work
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Event needing delete returns correctly'
);

-- Mark claimed event delete as synced to test the next delete variant
update event set meeting_in_sync = true where event_id = :'eventCanceledDeleteID';

-- Reopen soft-deleted event now that higher-priority delete work has drained
update event
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where event_id = :'eventDeletedID';

-- Soft-deleted event with meeting returns for delete
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "event_id": "%s",
        "join_url": "https://zoom.us/j/event-deleted",
        "meeting_id": "%s",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "event-deleted"
    }$json$,
        :'eventDeletedID',
        :'meetingEventDeletedID'
    )::jsonb,
    'Soft-deleted event with meeting returns for delete'
);

-- Mark claimed event delete as synced to test the next delete variant
update event set meeting_in_sync = true where event_id = :'eventDeletedID';

-- Reopen unpublished event without meeting to prove it does not wedge the queue
update event
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where event_id = :'eventUnpublishedID';

-- Unpublished event without meeting returns for delete to be marked handled
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "event_id": "%s"
    }$json$,
        :'eventUnpublishedID'
    )::jsonb,
    'Unpublished event without meeting returns for delete'
);

-- Mark claimed event delete as synced to test the next delete variant
update event set meeting_in_sync = true where event_id = :'eventUnpublishedID';

-- Reopen unpublished event with meeting after the no-meeting variant is handled
update event
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where event_id = :'eventUnpublishedWithMeetingID';

-- Unpublished event with meeting returns for provider deletion
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Unpublished event with meeting returns for delete'
);

-- Mark claimed event delete as synced to test the next delete variant
update event set meeting_in_sync = true where event_id = :'eventUnpublishedWithMeetingID';

-- Reopen disabled event meeting after other event deletes for deterministic order
update event
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where event_id = :'eventDisabledID';

-- Event with meeting disabled triggers delete
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Event with meeting disabled triggers delete'
);

-- Mark claimed event delete as synced to test the final event delete variant
update event set meeting_in_sync = true where event_id = :'eventDisabledID';

-- Reopen canceled event that never had a provider meeting created
update event
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where event_id = :'eventCanceledNoMeetingID';

-- Event canceled before meeting creation returns for delete with null meeting fields
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "event_id": "%s"
    }$json$,
        :'eventCanceledNoMeetingID'
    )::jsonb,
    'Event canceled before meeting created returns with delete=true and null meeting fields'
);

-- Mark claimed event delete as synced so session delete work can be claimed
update event set meeting_in_sync = true where event_id = :'eventCanceledNoMeetingID';

-- Reopen canceled-parent session after event delete work is handled
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionDeleteID';

-- Session delete - returns canceled-parent session with delete=true
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Session needing delete returns correctly'
);

-- Mark claimed session delete as synced to test the next delete variant
update session set meeting_in_sync = true where session_id = :'sessionDeleteID';

-- Reopen soft-deleted-parent session after the canceled-parent variant is handled
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionDeletedParentID';

-- Session on soft-deleted event with meeting returns for delete
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "join_url": "https://zoom.us/j/session-deleted-parent",
        "meeting_id": "%s",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "session-deleted-parent",
        "session_id": "%s"
    }$json$,
        :'meetingSessionDeletedParentID',
        :'sessionDeletedParentID'
    )::jsonb,
    'Session on soft-deleted event with meeting returns for delete'
);

-- Mark claimed session delete as synced to test the no-meeting variant
update session set meeting_in_sync = true where session_id = :'sessionDeletedParentID';

-- Reopen canceled-parent session that never had a provider meeting created
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionCanceledNoMeetingID';

-- Session on canceled event before meeting creation returns for delete
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "session_id": "%s"
    }$json$,
        :'sessionCanceledNoMeetingID'
    )::jsonb,
    'Session on canceled event before meeting created returns with delete=true and null meeting fields'
);

-- Mark claimed session delete as synced to test unpublished session variants
update session set meeting_in_sync = true where session_id = :'sessionCanceledNoMeetingID';

-- Reopen unpublished-parent session without meeting for queue cleanup
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionUnpublishedNoMeetingID';

-- Session on unpublished event without meeting returns for delete to be handled
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "session_id": "%s"
    }$json$,
        :'sessionUnpublishedNoMeetingID'
    )::jsonb,
    'Session on unpublished event without meeting returns for delete'
);

-- Mark claimed session delete as synced to test the with-meeting variant
update session set meeting_in_sync = true where session_id = :'sessionUnpublishedNoMeetingID';

-- Reopen unpublished-parent session with meeting after the no-meeting variant
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionUnpublishedWithMeetingID';

-- Session on unpublished event with meeting returns for provider deletion
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Session on unpublished event with meeting returns for delete'
);

-- Mark claimed session delete as synced to test disabled session meetings
update session set meeting_in_sync = true where session_id = :'sessionUnpublishedWithMeetingID';

-- Reopen disabled session meeting after other session deletes are handled
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionDisabledID';

-- Session with meeting disabled returns for delete
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
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
    )::jsonb,
    'Session with meeting disabled returns for delete'
);

-- Mark claimed session delete as synced so only orphan work remains
update session set meeting_in_sync = true where session_id = :'sessionDisabledID';

-- Orphan meeting - already detached meeting rows are claimed for provider cleanup
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": true,
        "join_url": "https://zoom.us/j/orphan",
        "meeting_id": "%s",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "orphan"
    }$json$,
        :'meetingOrphanID'
    )::jsonb,
    'Orphan meeting returns with delete=true'
);
select isnt(
    (select sync_claimed_at from meeting where meeting_id = :'meetingOrphanID'),
    null,
    'Should claim orphan meeting'
);

-- Remove claimed orphan to expose the next orphan candidate
delete from meeting where meeting_id = :'meetingOrphanID';

-- Multiple orphan meetings - event delete cascades to session delete
-- The event meeting and session meeting both become detached provider meetings
delete from event where event_id = :'eventOrphanCascadeID';
select is(
    (claim_meeting_out_of_sync()->>'delete')::boolean,
    true,
    'First orphan meeting from hard-deleted event is claimed'
);

-- Remove the first claimed cascade orphan to expose the second one
delete from meeting
where sync_claimed_at is not null
  and meeting_id in (
      :'meetingEventOrphanCascadeID'::uuid,
      :'meetingSessionOrphanCascadeID'::uuid
);
select is(
    (claim_meeting_out_of_sync()->>'delete')::boolean,
    true,
    'Second orphan meeting from hard-deleted event is claimed'
);

-- Remove the second cascade orphan so the queue can drain
delete from meeting
where sync_claimed_at is not null
  and meeting_id in (
      :'meetingEventOrphanCascadeID'::uuid,
      :'meetingSessionOrphanCascadeID'::uuid
  );

-- In-sync and no-request rows are skipped once all candidates are handled
select is(
    claim_meeting_out_of_sync(),
    null::jsonb,
    'Empty queue returns null'
);

-- Imported past events and sessions are never claimed for provider create/update
update event
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where event_id = :'eventPastImportID';

-- Make the imported past session eligible except for its historical timestamp
update session
set meeting_in_sync = false,
    meeting_sync_claimed_at = null
where session_id = :'sessionPastImportID';
select is(
    claim_meeting_out_of_sync(),
    null::jsonb,
    'Past event and session automatic meetings are skipped'
);

-- Republished event triggers create instead of delete
-- Reset the previous delete claim so the durable claim function can pick it up
update event
set meeting_in_sync = false,
    meeting_provider_id = 'zoom',
    meeting_requested = true,
    meeting_sync_claimed_at = null,
    published = true
where event_id = :'eventUnpublishedID';
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    format(
        $json${
        "delete": false,
        "duration_secs": 3600,
        "event_id": "%s",
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "timezone": "UTC",
        "topic": "Event Unpublished Test"
    }$json$,
        :'eventUnpublishedID'
    )::jsonb,
    'Republished event triggers create'
);

-- The same claimed row is not returned again until its claim is released or synced
select is(
    claim_meeting_out_of_sync(),
    null::jsonb,
    'Should not return the same claimed owner again'
);

-- Claiming records ownership of the work but does not mark the owner as synced
select is(
    (select meeting_in_sync from event where event_id = :'eventUnpublishedID'),
    false,
    'Should not mark claimed owner as synced'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
