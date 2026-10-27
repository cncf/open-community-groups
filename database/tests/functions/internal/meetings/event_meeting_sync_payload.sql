-- Tests building the meeting sync claim payload of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3e7f0000-0000-0000-0000-000000000001'
\set eventCategoryID '3e7f0000-0000-0000-0000-000000000002'
\set eventCreateID '3e7f0000-0000-0000-0000-000000000003'
\set eventDeleteID '3e7f0000-0000-0000-0000-000000000004'
\set eventDeleteNoMeetingID '3e7f0000-0000-0000-0000-000000000005'
\set eventUpdateID '3e7f0000-0000-0000-0000-000000000006'
\set groupCategoryID '3e7f0000-0000-0000-0000-000000000007'
\set groupID '3e7f0000-0000-0000-0000-000000000008'
\set meetingDeleteID '3e7f0000-0000-0000-0000-000000000009'
\set meetingUpdateID '3e7f0000-0000-0000-0000-000000000010'
\set userHostID '3e7f0000-0000-0000-0000-000000000011'
\set userSpeakerID '3e7f0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community
select fx_community(:'communityID');

-- Event host also listed as an explicit meeting host
select fx_user(:'userHostID', jsonb_build_object(
    'email', 'event-payload-host@example.com',
    'username', 'event-payload-host'
));

-- Event speaker included in the create payload hosts
select fx_user(:'userSpeakerID', jsonb_build_object(
    'email', 'event-payload-speaker@example.com',
    'username', 'event-payload-speaker'
));

-- Baseline categories and group
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Claimed event needing create, with explicit hosts and a reserved host
select fx_event(:'eventCreateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-07-01 11:30:00+00',
    'event_kind_id', 'virtual',
    'meeting_hosts', array[
        'event-payload-explicit@example.com',
        'event-payload-host@example.com'
    ],
    'meeting_provider_host_user', 'event-payload-reserved@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_recording_requested', true,
    'meeting_requested', true,
    'meeting_sync_claimed_at', '2030-06-01 09:00:00+00',
    'name', 'Event Payload Create',
    'starts_at', '2030-07-01 10:00:00+00',
    'timezone', 'Europe/Madrid'
));

-- Claimed event with a disabled meeting whose stored meeting needs delete
select fx_event(:'eventDeleteID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-07-02 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_hosts', array['event-payload-delete-host@example.com'],
    'meeting_provider_host_user', 'event-payload-delete-reserved@example.com',
    'meeting_recording_requested', true,
    'meeting_requested', false,
    'meeting_sync_claimed_at', '2030-06-02 09:00:00+00',
    'name', 'Event Payload Delete',
    'starts_at', '2030-07-02 10:00:00+00',
    'timezone', 'Europe/Madrid'
));

-- Claimed canceled event needing delete before its meeting was created
select fx_event(:'eventDeleteNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', '2030-07-03 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_provider_id', 'zoom',
    'meeting_recording_requested', true,
    'meeting_requested', true,
    'meeting_sync_claimed_at', '2030-06-03 09:00:00+00',
    'name', 'Event Payload Delete No Meeting',
    'starts_at', '2030-07-03 10:00:00+00',
    'timezone', 'Europe/Madrid'
));

-- Claimed event needing update of its stored meeting, without hosts
select fx_event(:'eventUpdateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-07-04 12:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_provider_id', 'zoom',
    'meeting_recording_requested', false,
    'meeting_requested', true,
    'meeting_sync_claimed_at', '2030-06-04 09:00:00+00',
    'name', 'Event Payload Update',
    'starts_at', '2030-07-04 10:00:00+00',
    'timezone', 'Asia/Tokyo'
));

-- Host of the create event, duplicated in its explicit meeting hosts
insert into event_host (event_id, user_id)
values (:'eventCreateID', :'userHostID');

-- Speaker of the create event
insert into event_speaker (event_id, user_id, featured)
values (:'eventCreateID', :'userSpeakerID', false);

-- Stored meeting of the delete event
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    password
) values (
    :'meetingDeleteID',
    'https://zoom.us/j/event-payload-delete',
    'zoom',
    'event-payload-delete',

    :'eventDeleteID',
    'deletepass'
);

-- Stored meeting of the update event
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    password
) values (
    :'meetingUpdateID',
    'https://zoom.us/j/event-payload-update',
    'zoom',
    'event-payload-update',

    :'eventUpdateID',
    'updatepass'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should build the create payload with combined, deduplicated hosts and no meeting fields when no meeting exists
select is(
    event_meeting_sync_payload((select e from event e where e.event_id = :'eventCreateID'), false),
    format(
        $json${
            "delete": false,
            "duration_secs": 5400,
            "event_id": "%s",
            "hosts": [
                "event-payload-explicit@example.com",
                "event-payload-host@example.com",
                "event-payload-speaker@example.com"
            ],
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "provider_host_user_id": "event-payload-reserved@example.com",
            "timezone": "Europe/Madrid",
            "topic": "Event Payload Create"
        }$json$,
        :'eventCreateID'
    )::jsonb || jsonb_build_object(
        'starts_at', '2030-07-01 10:00:00+00'::timestamptz,
        'sync_claimed_at', '2030-06-01 09:00:00+00'::timestamptz,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventCreateID')
    ),
    'Should build the create payload with combined, deduplicated hosts and no meeting fields when no meeting exists'
);

-- Should build the delete payload with the provider of the stored meeting
select is(
    event_meeting_sync_payload((select e from event e where e.event_id = :'eventDeleteID'), true),
    format(
        $json${
            "delete": true,
            "event_id": "%s",
            "join_url": "https://zoom.us/j/event-payload-delete",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "password": "deletepass",
            "provider_host_user_id": "event-payload-delete-reserved@example.com",
            "provider_meeting_id": "event-payload-delete"
        }$json$,
        :'eventDeleteID',
        :'meetingDeleteID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', '2030-06-02 09:00:00+00'::timestamptz,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventDeleteID')
    ),
    'Should build the delete payload with the provider of the stored meeting'
);

-- Should build the delete payload without meeting fields when no meeting exists
select is(
    event_meeting_sync_payload((select e from event e where e.event_id = :'eventDeleteNoMeetingID'), true),
    format(
        $json${
            "delete": true,
            "event_id": "%s"
        }$json$,
        :'eventDeleteNoMeetingID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', '2030-06-03 09:00:00+00'::timestamptz,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventDeleteNoMeetingID')
    ),
    'Should build the delete payload without meeting fields when no meeting exists'
);

-- Should build the update payload with the stored meeting fields
select is(
    event_meeting_sync_payload((select e from event e where e.event_id = :'eventUpdateID'), false),
    format(
        $json${
            "delete": false,
            "duration_secs": 7200,
            "event_id": "%s",
            "join_url": "https://zoom.us/j/event-payload-update",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": false,
            "password": "updatepass",
            "provider_meeting_id": "event-payload-update",
            "timezone": "Asia/Tokyo",
            "topic": "Event Payload Update"
        }$json$,
        :'eventUpdateID',
        :'meetingUpdateID'
    )::jsonb || jsonb_build_object(
        'starts_at', '2030-07-04 10:00:00+00'::timestamptz,
        'sync_claimed_at', '2030-06-04 09:00:00+00'::timestamptz,
        'sync_state_hash', get_event_meeting_sync_state_hash(:'eventUpdateID')
    ),
    'Should build the update payload with the stored meeting fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
