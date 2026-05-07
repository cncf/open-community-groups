-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(26);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000001511'
\set communityID '00000000-0000-0000-0000-000000001501'
\set eventCanceledDeleteID '00000000-0000-0000-0000-000000001515'
\set eventCanceledNoMeetingID '00000000-0000-0000-0000-000000001519'
\set eventCreateID '00000000-0000-0000-0000-000000001512'
\set eventDeletedID '00000000-0000-0000-0000-000000001526'
\set eventDisabledID '00000000-0000-0000-0000-000000001518'
\set eventInSyncID '00000000-0000-0000-0000-000000001521'
\set eventNoRequestID '00000000-0000-0000-0000-000000001522'
\set eventOrphanCascadeID '00000000-0000-0000-0000-000000001527'
\set eventPastImportID '00000000-0000-0000-0000-000000001551'
\set eventUnpublishedID '00000000-0000-0000-0000-000000001517'
\set eventUnpublishedWithMeetingID '00000000-0000-0000-0000-000000001528'
\set eventUpdateID '00000000-0000-0000-0000-000000001513'
\set eventWithSessionsID '00000000-0000-0000-0000-000000001514'
\set groupCategoryID '00000000-0000-0000-0000-000000001510'
\set groupID '00000000-0000-0000-0000-000000001502'
\set meetingDisabledID '00000000-0000-0000-0000-000000001538'
\set meetingEventCanceledDeleteID '00000000-0000-0000-0000-000000001535'
\set meetingEventDeletedID '00000000-0000-0000-0000-000000001539'
\set meetingEventOrphanCascadeID '00000000-0000-0000-0000-000000001540'
\set meetingEventUnpublishedID '00000000-0000-0000-0000-000000001544'
\set meetingEventUpdateID '00000000-0000-0000-0000-000000001533'
\set meetingOrphanID '00000000-0000-0000-0000-000000001537'
\set meetingSessionDeletedParentID '00000000-0000-0000-0000-000000001545'
\set meetingSessionDeleteID '00000000-0000-0000-0000-000000001536'
\set meetingSessionDisabledID '00000000-0000-0000-0000-000000001546'
\set meetingSessionOrphanCascadeID '00000000-0000-0000-0000-000000001547'
\set meetingSessionUnpublishedID '00000000-0000-0000-0000-000000001548'
\set meetingSessionUpdateID '00000000-0000-0000-0000-000000001534'
\set sessionCanceledNoMeetingID '00000000-0000-0000-0000-000000001529'
\set sessionCreateID '00000000-0000-0000-0000-000000001523'
\set sessionDeletedParentID '00000000-0000-0000-0000-000000001530'
\set sessionDeleteID '00000000-0000-0000-0000-000000001525'
\set sessionDisabledID '00000000-0000-0000-0000-000000001531'
\set sessionOrphanCascadeID '00000000-0000-0000-0000-000000001532'
\set sessionPastImportID '00000000-0000-0000-0000-000000001552'
\set sessionUnpublishedNoMeetingID '00000000-0000-0000-0000-000000001549'
\set sessionUnpublishedWithMeetingID '00000000-0000-0000-0000-000000001550'
\set sessionUpdateID '00000000-0000-0000-0000-000000001524'
\set userEventHostID '00000000-0000-0000-0000-000000001541'
\set userEventSpeakerID '00000000-0000-0000-0000-000000001542'
\set userSessionSpeakerID '00000000-0000-0000-0000-000000001543'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Users for event_host, event_speaker, and session_speaker host aggregation
insert into "user" (user_id, auth_hash, email, username) values
    (:'userEventHostID', 'hash1', 'eventhost@example.com', 'eventhost'),
    (:'userEventSpeakerID', 'hash2', 'eventspeaker@example.com', 'eventspeaker'),
    (:'userSessionSpeakerID', 'hash3', 'sessionspeaker@example.com', 'sessionspeaker');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, description)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group', 'A test group');

-- Event candidates and exclusions
-- Delete-focused rows that could interfere start in sync and are reopened later
insert into event (
    capacity,
    canceled,
    deleted,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_hosts,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values
(
    100,
    false,
    false,
    'Event create test',
    '2026-06-01 11:00:00+00',
    :'categoryID',
    :'eventCreateID',
    'virtual',
    :'groupID',
    array['explicit@example.com'],
    false,
    'zoom',
    true,
    'Event Create Test',
    true,
    'event-create-test',
    '2026-06-01 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Event update test',
    '2026-06-02 12:00:00+00',
    :'categoryID',
    :'eventUpdateID',
    'virtual',
    :'groupID',
    null,
    false,
    'zoom',
    true,
    'Event Update Test',
    true,
    'event-update-test',
    '2026-06-02 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Parent event for sessions',
    '2026-06-03 12:00:00+00',
    :'categoryID',
    :'eventWithSessionsID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event With Sessions',
    true,
    'event-with-sessions',
    '2026-06-03 10:00:00+00',
    'UTC'
),
(
    100,
    true,
    false,
    'Canceled event delete test',
    '2026-06-04 11:00:00+00',
    :'categoryID',
    :'eventCanceledDeleteID',
    'virtual',
    :'groupID',
    null,
    false,
    'zoom',
    true,
    'Event Canceled Delete Test',
    false,
    'event-canceled-delete-test',
    '2026-06-04 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    true,
    'Soft deleted event test',
    '2026-06-04 12:00:00+00',
    :'categoryID',
    :'eventDeletedID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event Deleted Test',
    false,
    'event-deleted-test',
    '2026-06-04 11:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Unpublished event test',
    '2026-06-05 11:00:00+00',
    :'categoryID',
    :'eventUnpublishedID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event Unpublished Test',
    false,
    'event-unpublished-test',
    '2026-06-05 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Unpublished event with meeting test',
    '2026-06-05 12:00:00+00',
    :'categoryID',
    :'eventUnpublishedWithMeetingID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event Unpublished With Meeting Test',
    false,
    'event-unpublished-with-meeting-test',
    '2026-06-05 11:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Meeting disabled test',
    '2026-06-06 11:00:00+00',
    :'categoryID',
    :'eventDisabledID',
    'virtual',
    :'groupID',
    null,
    true,
    null,
    false,
    'Event Disabled Test',
    true,
    'event-disabled-test',
    '2026-06-06 10:00:00+00',
    'UTC'
),
(
    100,
    true,
    false,
    'Canceled before meeting creation',
    '2026-06-07 11:00:00+00',
    :'categoryID',
    :'eventCanceledNoMeetingID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event Canceled No Meeting Test',
    false,
    'event-canceled-no-meeting-test',
    '2026-06-07 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'In-sync event exclusion',
    '2026-06-08 11:00:00+00',
    :'categoryID',
    :'eventInSyncID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event In Sync Test',
    true,
    'event-in-sync-test',
    '2026-06-08 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'No meeting request exclusion',
    '2026-06-09 11:00:00+00',
    :'categoryID',
    :'eventNoRequestID',
    'virtual',
    :'groupID',
    null,
    true,
    null,
    false,
    'Event No Request Test',
    true,
    'event-no-request-test',
    '2026-06-09 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Past import event exclusion',
    '2020-06-11 11:00:00+00',
    :'categoryID',
    :'eventPastImportID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Past Import Event Test',
    true,
    'past-import-event-test',
    '2020-06-11 10:00:00+00',
    'UTC'
),
(
    100,
    false,
    false,
    'Event for hard-delete orphan meetings',
    '2026-06-10 11:00:00+00',
    :'categoryID',
    :'eventOrphanCascadeID',
    'virtual',
    :'groupID',
    null,
    true,
    'zoom',
    true,
    'Event Orphan Cascade Test',
    true,
    'event-orphan-cascade-test',
    '2026-06-10 10:00:00+00',
    'UTC'
);

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
    '2026-06-03 10:30:00+00',
    :'eventWithSessionsID',
    array['sessionhost@example.com'],
    false,
    'zoom',
    true,
    'Session Create Test',
    :'sessionCreateID',
    'virtual',
    '2026-06-03 10:00:00+00'
),
(
    '2026-06-03 11:30:00+00',
    :'eventWithSessionsID',
    null,
    false,
    'zoom',
    true,
    'Session Update Test',
    :'sessionUpdateID',
    'virtual',
    '2026-06-03 11:00:00+00'
),
(
    '2026-06-04 10:30:00+00',
    :'eventCanceledDeleteID',
    null,
    true,
    'zoom',
    true,
    'Session Delete Test',
    :'sessionDeleteID',
    'virtual',
    '2026-06-04 10:00:00+00'
),
(
    '2026-06-04 11:30:00+00',
    :'eventDeletedID',
    null,
    true,
    'zoom',
    true,
    'Session Deleted Parent Test',
    :'sessionDeletedParentID',
    'virtual',
    '2026-06-04 11:00:00+00'
),
(
    '2026-06-07 10:30:00+00',
    :'eventCanceledNoMeetingID',
    null,
    true,
    'zoom',
    true,
    'Session Canceled No Meeting Test',
    :'sessionCanceledNoMeetingID',
    'virtual',
    '2026-06-07 10:00:00+00'
),
(
    '2026-06-05 10:30:00+00',
    :'eventUnpublishedID',
    null,
    true,
    'zoom',
    true,
    'Session Unpublished No Meeting Test',
    :'sessionUnpublishedNoMeetingID',
    'virtual',
    '2026-06-05 10:00:00+00'
),
(
    '2026-06-05 11:00:00+00',
    :'eventUnpublishedID',
    null,
    true,
    'zoom',
    true,
    'Session Unpublished With Meeting Test',
    :'sessionUnpublishedWithMeetingID',
    'virtual',
    '2026-06-05 10:30:00+00'
),
(
    '2026-06-03 12:00:00+00',
    :'eventWithSessionsID',
    null,
    true,
    null,
    false,
    'Session Disabled Test',
    :'sessionDisabledID',
    'virtual',
    '2026-06-03 11:30:00+00'
),
(
    '2026-06-10 10:30:00+00',
    :'eventOrphanCascadeID',
    null,
    true,
    'zoom',
    true,
    'Session Orphan Cascade Test',
    :'sessionOrphanCascadeID',
    'virtual',
    '2026-06-10 10:00:00+00'
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
insert into event_speaker (event_id, user_id, featured)
values (:'eventCreateID', :'userEventSpeakerID', false);
-- eventWithSessionsID and sessionCreateID combine parent host and session speaker
insert into event_host (event_id, user_id)
values (:'eventWithSessionsID', :'userEventHostID');
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
    '{
        "delete": false,
        "duration_secs": 3600,
        "event_id": "00000000-0000-0000-0000-000000001512",
        "hosts": ["eventhost@example.com", "eventspeaker@example.com", "explicit@example.com"],
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "timezone": "UTC",
        "topic": "Event Create Test"
    }'::jsonb,
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
    '{
        "delete": false,
        "duration_secs": 7200,
        "event_id": "00000000-0000-0000-0000-000000001513",
        "join_url": "https://zoom.us/j/event-update",
        "meeting_id": "00000000-0000-0000-0000-000000001533",
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "password": "eventpass",
        "provider_meeting_id": "event-update",
        "timezone": "UTC",
        "topic": "Event Update Test"
    }'::jsonb,
    'Event needing update returns correctly'
);

-- Mark claimed event as synced to advance to the next queue item
update event set meeting_in_sync = true where event_id = :'eventUpdateID';

-- Session create - returns session with delete=false and no meeting row
-- Priority: session create/update work is claimed before delete work
-- Hosts include explicit meeting_hosts, parent event_host, and session_speaker emails
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    '{
        "delete": false,
        "duration_secs": 1800,
        "hosts": ["eventhost@example.com", "sessionhost@example.com", "sessionspeaker@example.com"],
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "session_id": "00000000-0000-0000-0000-000000001523",
        "timezone": "UTC",
        "topic": "Session Create Test"
    }'::jsonb,
    'Session needing create returns correctly'
);

-- Mark claimed session as synced to advance to the next queue item
update session set meeting_in_sync = true where session_id = :'sessionCreateID';

-- Session update - returns session with delete=false and existing provider fields
-- Hosts include parent event_host emails only
select is(
    claim_meeting_out_of_sync() - 'starts_at' - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    '{
        "delete": false,
        "duration_secs": 1800,
        "hosts": ["eventhost@example.com"],
        "join_url": "https://zoom.us/j/session-update",
        "meeting_id": "00000000-0000-0000-0000-000000001534",
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "password": "sessionpass",
        "provider_meeting_id": "session-update",
        "session_id": "00000000-0000-0000-0000-000000001524",
        "timezone": "UTC",
        "topic": "Session Update Test"
    }'::jsonb,
    'Session needing update returns correctly'
);

-- Mark claimed session as synced to advance to the next queue item
update session set meeting_in_sync = true where session_id = :'sessionUpdateID';

-- Event delete - returns canceled event with delete=true
-- Priority: delete operations come after event and session create/update work
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    '{
        "delete": true,
        "event_id": "00000000-0000-0000-0000-000000001515",
        "join_url": "https://zoom.us/j/event-canceled-delete",
        "meeting_id": "00000000-0000-0000-0000-000000001535",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "event-canceled-delete"
    }'::jsonb,
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
    '{
        "delete": true,
        "event_id": "00000000-0000-0000-0000-000000001526",
        "join_url": "https://zoom.us/j/event-deleted",
        "meeting_id": "00000000-0000-0000-0000-000000001539",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "event-deleted"
    }'::jsonb,
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
    '{
        "delete": true,
        "event_id": "00000000-0000-0000-0000-000000001517"
    }'::jsonb,
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
    '{
        "delete": true,
        "event_id": "00000000-0000-0000-0000-000000001528",
        "join_url": "https://zoom.us/j/event-unpublished",
        "meeting_id": "00000000-0000-0000-0000-000000001544",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "event-unpublished"
    }'::jsonb,
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
    '{
        "delete": true,
        "event_id": "00000000-0000-0000-0000-000000001518",
        "join_url": "https://zoom.us/j/event-disabled",
        "meeting_id": "00000000-0000-0000-0000-000000001538",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "event-disabled"
    }'::jsonb,
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
    '{
        "delete": true,
        "event_id": "00000000-0000-0000-0000-000000001519"
    }'::jsonb,
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
    '{
        "delete": true,
        "join_url": "https://zoom.us/j/session-delete",
        "meeting_id": "00000000-0000-0000-0000-000000001536",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "session-delete",
        "session_id": "00000000-0000-0000-0000-000000001525"
    }'::jsonb,
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
    '{
        "delete": true,
        "join_url": "https://zoom.us/j/session-deleted-parent",
        "meeting_id": "00000000-0000-0000-0000-000000001545",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "session-deleted-parent",
        "session_id": "00000000-0000-0000-0000-000000001530"
    }'::jsonb,
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
    '{
        "delete": true,
        "session_id": "00000000-0000-0000-0000-000000001529"
    }'::jsonb,
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
    '{
        "delete": true,
        "session_id": "00000000-0000-0000-0000-000000001549"
    }'::jsonb,
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
    '{
        "delete": true,
        "join_url": "https://zoom.us/j/session-unpublished",
        "meeting_id": "00000000-0000-0000-0000-000000001548",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "session-unpublished",
        "session_id": "00000000-0000-0000-0000-000000001550"
    }'::jsonb,
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
    '{
        "delete": true,
        "join_url": "https://zoom.us/j/session-disabled",
        "meeting_id": "00000000-0000-0000-0000-000000001546",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "session-disabled",
        "session_id": "00000000-0000-0000-0000-000000001531"
    }'::jsonb,
    'Session with meeting disabled returns for delete'
);

-- Mark claimed session delete as synced so only orphan work remains
update session set meeting_in_sync = true where session_id = :'sessionDisabledID';

-- Orphan meeting - already detached meeting rows are claimed for provider cleanup
select is(
    claim_meeting_out_of_sync() - 'provider_host_user_id' - 'sync_claimed_at' - 'sync_state_hash',
    '{
        "delete": true,
        "join_url": "https://zoom.us/j/orphan",
        "meeting_id": "00000000-0000-0000-0000-000000001537",
        "meeting_provider_id": "zoom",
        "provider_meeting_id": "orphan"
    }'::jsonb,
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
    '{
        "delete": false,
        "duration_secs": 3600,
        "event_id": "00000000-0000-0000-0000-000000001517",
        "meeting_provider_id": "zoom",
        "meeting_recording_requested": true,
        "timezone": "UTC",
        "topic": "Event Unpublished Test"
    }'::jsonb,
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
