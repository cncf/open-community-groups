-- Tests building the meeting sync claim payload of a session.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3e800000-0000-0000-0000-000000000001'
\set eventCategoryID '3e800000-0000-0000-0000-000000000002'
\set eventID '3e800000-0000-0000-0000-000000000003'
\set eventNoRecordingID '3e800000-0000-0000-0000-000000000004'
\set groupCategoryID '3e800000-0000-0000-0000-000000000005'
\set groupID '3e800000-0000-0000-0000-000000000006'
\set meetingDeleteID '3e800000-0000-0000-0000-000000000007'
\set meetingUpdateID '3e800000-0000-0000-0000-000000000008'
\set sessionCreateID '3e800000-0000-0000-0000-000000000009'
\set sessionDeleteID '3e800000-0000-0000-0000-000000000010'
\set sessionDeleteNoMeetingID '3e800000-0000-0000-0000-000000000011'
\set sessionNoRecordingID '3e800000-0000-0000-0000-000000000012'
\set sessionUpdateID '3e800000-0000-0000-0000-000000000013'
\set userEventHostID '3e800000-0000-0000-0000-000000000014'
\set userEventSpeakerID '3e800000-0000-0000-0000-000000000015'
\set userSessionSpeakerID '3e800000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community
select fx_community(:'communityID');

-- Parent event host also listed as an explicit session meeting host
select fx_user(:'userEventHostID', jsonb_build_object(
    'email', 'session-payload-event-host@example.com',
    'username', 'session-payload-event-host'
));

-- Parent event speaker left out of the session payload hosts
select fx_user(:'userEventSpeakerID', jsonb_build_object(
    'email', 'session-payload-event-speaker@example.com',
    'username', 'session-payload-event-speaker'
));

-- Session speaker included in the create payload hosts
select fx_user(:'userSessionSpeakerID', jsonb_build_object(
    'email', 'session-payload-speaker@example.com',
    'username', 'session-payload-speaker'
));

-- Baseline categories and group
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Parent event requesting recordings in the Madrid timezone
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-08-01 18:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_recording_requested', true,
    'meeting_requested', false,
    'starts_at', '2030-08-01 09:00:00+00',
    'timezone', 'Europe/Madrid'
));

-- Parent event declining recordings in the Tokyo timezone
select fx_event(:'eventNoRecordingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2030-08-02 18:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_recording_requested', false,
    'meeting_requested', false,
    'starts_at', '2030-08-02 09:00:00+00',
    'timezone', 'Asia/Tokyo'
));

-- Host of the parent event, duplicated in the create session meeting hosts
insert into event_host (event_id, user_id)
values (:'eventID', :'userEventHostID');

-- Speaker of the parent event
insert into event_speaker (event_id, user_id, featured)
values (:'eventID', :'userEventSpeakerID', false);

-- Claimed session needing create, with explicit hosts and a reserved host
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,

    ends_at,
    meeting_hosts,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionCreateID',
    :'eventID',
    'Session Payload Create',
    'virtual',
    '2030-08-01 10:00:00+00',

    '2030-08-01 10:45:00+00',
    array['session-payload-event-host@example.com', 'session-payload-explicit@example.com'],
    'session-payload-reserved@example.com',
    'zoom',
    true,
    '2030-07-01 09:00:00+00'
);

-- Claimed session with a disabled meeting whose stored meeting needs delete
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,

    ends_at,
    meeting_hosts,
    meeting_provider_host_user,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionDeleteID',
    :'eventID',
    'Session Payload Delete',
    'virtual',
    '2030-08-01 11:00:00+00',

    '2030-08-01 11:30:00+00',
    array['session-payload-delete-host@example.com'],
    'session-payload-delete-reserved@example.com',
    false,
    '2030-07-02 09:00:00+00'
);

-- Claimed session needing delete before its meeting was created
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,

    ends_at,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionDeleteNoMeetingID',
    :'eventID',
    'Session Payload Delete No Meeting',
    'virtual',
    '2030-08-01 12:00:00+00',

    '2030-08-01 12:30:00+00',
    'zoom',
    true,
    '2030-07-03 09:00:00+00'
);

-- Claimed session needing create on the parent event declining recordings
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,

    ends_at,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionNoRecordingID',
    :'eventNoRecordingID',
    'Session Payload No Recording',
    'virtual',
    '2030-08-02 10:00:00+00',

    '2030-08-02 11:00:00+00',
    'zoom',
    true,
    '2030-07-04 09:00:00+00'
);

-- Claimed session needing update of its stored meeting, without session hosts
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,

    ends_at,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at
) values (
    :'sessionUpdateID',
    :'eventID',
    'Session Payload Update',
    'virtual',
    '2030-08-01 13:00:00+00',

    '2030-08-01 14:30:00+00',
    'zoom',
    true,
    '2030-07-05 09:00:00+00'
);

-- Stored meeting of the delete session
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    password,
    session_id
) values (
    :'meetingDeleteID',
    'https://zoom.us/j/session-payload-delete',
    'zoom',
    'session-payload-delete',

    'deletepass',
    :'sessionDeleteID'
);

-- Stored meeting of the update session
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    password,
    session_id
) values (
    :'meetingUpdateID',
    'https://zoom.us/j/session-payload-update',
    'zoom',
    'session-payload-update',

    'updatepass',
    :'sessionUpdateID'
);

-- Speaker of the create session
insert into session_speaker (session_id, user_id, featured)
values (:'sessionCreateID', :'userSessionSpeakerID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should build the create payload with combined, deduplicated hosts and no meeting fields when no meeting exists
select is(
    session_meeting_sync_payload((select s from session s where s.session_id = :'sessionCreateID'), false),
    format(
        $json${
            "delete": false,
            "duration_secs": 2700,
            "hosts": [
                "session-payload-event-host@example.com",
                "session-payload-explicit@example.com",
                "session-payload-speaker@example.com"
            ],
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "provider_host_user_id": "session-payload-reserved@example.com",
            "session_id": "%s",
            "timezone": "Europe/Madrid",
            "topic": "Session Payload Create"
        }$json$,
        :'sessionCreateID'
    )::jsonb || jsonb_build_object(
        'starts_at', '2030-08-01 10:00:00+00'::timestamptz,
        'sync_claimed_at', '2030-07-01 09:00:00+00'::timestamptz,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionCreateID')
    ),
    'Should build the create payload with combined, deduplicated hosts and no meeting fields when no meeting exists'
);

-- Should build the delete payload with the provider of the stored meeting
select is(
    session_meeting_sync_payload((select s from session s where s.session_id = :'sessionDeleteID'), true),
    format(
        $json${
            "delete": true,
            "join_url": "https://zoom.us/j/session-payload-delete",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "password": "deletepass",
            "provider_host_user_id": "session-payload-delete-reserved@example.com",
            "provider_meeting_id": "session-payload-delete",
            "session_id": "%s"
        }$json$,
        :'meetingDeleteID',
        :'sessionDeleteID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', '2030-07-02 09:00:00+00'::timestamptz,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionDeleteID')
    ),
    'Should build the delete payload with the provider of the stored meeting'
);

-- Should build the delete payload without meeting fields when no meeting exists
select is(
    session_meeting_sync_payload((select s from session s where s.session_id = :'sessionDeleteNoMeetingID'), true),
    format(
        $json${
            "delete": true,
            "session_id": "%s"
        }$json$,
        :'sessionDeleteNoMeetingID'
    )::jsonb || jsonb_build_object(
        'sync_claimed_at', '2030-07-03 09:00:00+00'::timestamptz,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionDeleteNoMeetingID')
    ),
    'Should build the delete payload without meeting fields when no meeting exists'
);

-- Should build the update payload with the stored meeting fields
select is(
    session_meeting_sync_payload((select s from session s where s.session_id = :'sessionUpdateID'), false),
    format(
        $json${
            "delete": false,
            "duration_secs": 5400,
            "hosts": ["session-payload-event-host@example.com"],
            "join_url": "https://zoom.us/j/session-payload-update",
            "meeting_id": "%s",
            "meeting_provider_id": "zoom",
            "meeting_recording_requested": true,
            "password": "updatepass",
            "provider_meeting_id": "session-payload-update",
            "session_id": "%s",
            "timezone": "Europe/Madrid",
            "topic": "Session Payload Update"
        }$json$,
        :'meetingUpdateID',
        :'sessionUpdateID'
    )::jsonb || jsonb_build_object(
        'starts_at', '2030-08-01 13:00:00+00'::timestamptz,
        'sync_claimed_at', '2030-07-05 09:00:00+00'::timestamptz,
        'sync_state_hash', get_session_meeting_sync_state_hash(:'sessionUpdateID')
    ),
    'Should build the update payload with the stored meeting fields'
);

-- Should take the recording preference and timezone from the parent event
select is(
    (
        select jsonb_build_object(
            'meeting_recording_requested', p.payload -> 'meeting_recording_requested',
            'timezone', p.payload -> 'timezone'
        )
        from (
            select session_meeting_sync_payload(s, false) as payload
            from session s
            where s.session_id = :'sessionNoRecordingID'
        ) p
    ),
    '{"meeting_recording_requested": false, "timezone": "Asia/Tokyo"}'::jsonb,
    'Should take the recording preference and timezone from the parent event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
