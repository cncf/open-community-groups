-- Tests deriving the session meeting sync state from the stored rows and an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a150000-0000-0000-0000-000000000003'
\set eventCategoryID '3a150000-0000-0000-0000-000000000004'
\set groupCategoryID '3a150000-0000-0000-0000-000000000005'
\set groupID '3a150000-0000-0000-0000-000000000006'
\set hostedEventID '3a150000-0000-0000-0000-000000000007'
\set hostedSessionID '3a150000-0000-0000-0000-000000000008'
\set spokenEventID '3a150000-0000-0000-0000-000000000009'
\set spokenSessionID '3a150000-0000-0000-0000-000000000010'
\set user1ID '3a150000-0000-0000-0000-000000000001'
\set user2ID '3a150000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');

-- Event whose host rows are compared with the payload
select fx_event(:'hostedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-06-01 11:00:00-04',
    'event_kind_id', 'virtual',
    'starts_at', '2025-06-01 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Event whose session speaker rows are compared with the payload
select fx_event(:'spokenEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-06-01 11:00:00-04',
    'event_kind_id', 'virtual',
    'starts_at', '2025-06-01 10:00:00-04',
    'timezone', 'America/New_York'
));

-- Host of the hosted event
insert into event_host (event_id, user_id)
values (:'hostedEventID', :'user1ID');

-- Synced meeting session of the hosted event
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_provider_id,
    meeting_requested
) values (
    :'hostedSessionID',
    :'hostedEventID',
    'Session One',
    'virtual',
    '2025-06-01 10:15:00-04',
    '2025-06-01 10:45:00-04',
    'zoom',
    true
);

-- Synced meeting session of the spoken event
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_provider_id,
    meeting_requested
) values (
    :'spokenSessionID',
    :'spokenEventID',
    'Session One',
    'virtual',
    '2025-06-01 10:15:00-04',
    '2025-06-01 10:45:00-04',
    'zoom',
    true
);

-- Speaker of the spoken session
insert into session_speaker (session_id, user_id, featured)
values (:'spokenSessionID', :'user1ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- All fields remain in sync so meeting_in_sync stays true
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session all fields in sync returns true'
);

-- Sub-second precision in the stored row does not desync a payload with whole seconds
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00.250-04:00",
            "ends_at": "2025-06-01T10:45:00.750-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session stored sub-second precision keeps sync'
);

-- Meeting disabled after being enabled returns false to trigger deletion
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": false
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting disabled after being enabled returns false'
);

-- Re-enabling meeting after it was disabled desyncs meeting_in_sync
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": false
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting re-enabled after disable desyncs meeting'
);

-- Missing meeting_requested with previously enabled meeting returns false
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00"
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting requested missing with previous enabled returns false'
);

-- Missing meeting_requested without a previous meeting returns null
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00"
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00"
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    null::boolean,
    'Session without a meeting before or after returns null'
);

-- Name change causes meeting to be out of sync
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Renamed Session",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session name change desyncs meeting'
);

-- Schedule change (start or end) desyncs meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session schedule change desyncs meeting'
);

-- Event timezone change desyncs session meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T16:15:00",
            "ends_at": "2025-06-01T16:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "Europe/Madrid"}'::jsonb
    ),
    false,
    'Event timezone change desyncs session meeting'
);

-- Started synced session changes stay archived instead of creating provider update work
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'meeting_in_sync', true,
            'meeting_requested', true,
            'name', 'Started Session',
            'session_kind_id', 'virtual',
            'starts_at', current_timestamp - interval '2 hours'
        )),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind', 'virtual',
            'meeting_requested', true,
            'name', 'Started Session Updated',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS')
        ),
        jsonb_populate_record(null::event, '{"timezone": "UTC"}'::jsonb),
        '{"timezone": "UTC"}'::jsonb
    ),
    true,
    'Started synced session meeting changes stay in sync'
);

-- Started session meeting disabled after being enabled still triggers deletion
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'meeting_in_sync', true,
            'meeting_requested', true,
            'name', 'Started Session',
            'session_kind_id', 'virtual',
            'starts_at', current_timestamp - interval '2 hours'
        )),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind', 'virtual',
            'meeting_requested', false,
            'name', 'Started Session',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS')
        ),
        jsonb_populate_record(null::event, '{"timezone": "UTC"}'::jsonb),
        '{"timezone": "UTC"}'::jsonb
    ),
    false,
    'Started session meeting disabled after being enabled returns false'
);

-- Started pending session remains out of sync
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'meeting_in_sync', false,
            'meeting_requested', true,
            'name', 'Started Pending Session',
            'session_kind_id', 'virtual',
            'starts_at', current_timestamp - interval '2 hours'
        )),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind', 'virtual',
            'meeting_requested', true,
            'name', 'Started Pending Session Updated',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS')
        ),
        jsonb_populate_record(null::event, '{"timezone": "UTC"}'::jsonb),
        '{"timezone": "UTC"}'::jsonb
    ),
    false,
    'Started pending session meeting stays out of sync'
);

-- Parent event recording preference change desyncs session meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{
            "timezone": "America/New_York",
            "meeting_recording_requested": true
        }'::jsonb),
        '{
            "timezone": "America/New_York",
            "meeting_recording_requested": false
        }'::jsonb
    ),
    false,
    'Parent event recording preference change desyncs session meeting'
);

-- Kind change from hybrid to in-person desyncs meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "hybrid",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "in-person",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session kind change from hybrid to in-person desyncs meeting'
);

-- Kind change from virtual to in-person desyncs meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "in-person",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session kind change from virtual to in-person desyncs meeting'
);

-- meeting_hosts unchanged keeps sync
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session meeting_hosts unchanged keeps sync'
);

-- meeting_hosts change desyncs meeting
select is(
    is_session_meeting_in_sync(
        jsonb_populate_record(null::session, '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": "2025-06-01T10:15:00-04:00",
            "ends_at": "2025-06-01T10:45:00-04:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb,
        jsonb_populate_record(null::event, '{"timezone": "America/New_York"}'::jsonb),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting_hosts change desyncs meeting'
);

-- Event hosts unchanged keeps sync
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'hostedSessionID'),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true
        }'::jsonb,
        (select e from event e where e.event_id = :'hostedEventID'),
        format(
            '{"timezone": "America/New_York", "hosts": ["%s"]}',
            :'user1ID'
        )::jsonb
    ),
    true,
    'Event hosts unchanged keeps session sync'
);

-- Event hosts change desyncs session meeting
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'hostedSessionID'),
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true
        }'::jsonb,
        (select e from event e where e.event_id = :'hostedEventID'),
        format(
            '{"timezone": "America/New_York", "hosts": ["%s"]}',
            :'user2ID'
        )::jsonb
    ),
    false,
    'Event hosts change desyncs session meeting'
);

-- Session speakers unchanged keeps sync
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'spokenSessionID'),
        format(
            '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "speakers": [{"user_id": "%s", "featured": false}]
        }',
            :'user1ID'
        )::jsonb,
        (select e from event e where e.event_id = :'spokenEventID'),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session speakers unchanged keeps sync'
);

-- Session speakers change desyncs meeting
select is(
    is_session_meeting_in_sync(
        (select s from session s where s.session_id = :'spokenSessionID'),
        format(
            '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "speakers": [{"user_id": "%s", "featured": false}]
        }',
            :'user2ID'
        )::jsonb,
        (select e from event e where e.event_id = :'spokenEventID'),
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session speakers change desyncs meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
