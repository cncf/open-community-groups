-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- TESTS
-- ============================================================================

-- All fields remain in sync so meeting_in_sync stays true
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    true,
    'Event all fields in sync returns true'
);

-- Meeting disabled after being enabled returns false to trigger deletion
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": false
        }'::jsonb
    ),
    false,
    'Event meeting disabled after being enabled returns false'
);

-- Re-enabling meeting after it was disabled desyncs meeting_in_sync
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": false
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event meeting re-enabled after disable desyncs meeting'
);

-- Missing meeting_requested with previously enabled meeting returns false
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00"
        }'::jsonb
    ),
    false,
    'Event meeting requested missing with previous enabled returns false'
);

-- Name change causes meeting to be out of sync
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Renamed Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event name change desyncs meeting'
);

-- Schedule change (start or end) desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T11:00:00",
            "ends_at": "2025-06-01T12:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event schedule change desyncs meeting'
);

-- Timezone change desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/Chicago",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event timezone change desyncs meeting'
);

-- Started synced event changes stay archived instead of creating provider update work
select is(
    is_event_meeting_in_sync(
        jsonb_build_object(
            'ends_at', floor(extract(epoch from current_timestamp - interval '1 hour')),
            'meeting_in_sync', true,
            'meeting_recording_requested', true,
            'meeting_requested', true,
            'name', 'Started Event',
            'starts_at', floor(extract(epoch from current_timestamp - interval '2 hours')),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'virtual',
            'meeting_recording_requested', false,
            'meeting_requested', true,
            'name', 'Started Event Updated',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    true,
    'Started synced event meeting changes stay in sync'
);

-- Started event meeting disabled after being enabled still triggers deletion
select is(
    is_event_meeting_in_sync(
        jsonb_build_object(
            'ends_at', floor(extract(epoch from current_timestamp - interval '1 hour')),
            'meeting_in_sync', true,
            'meeting_requested', true,
            'name', 'Started Event',
            'starts_at', floor(extract(epoch from current_timestamp - interval '2 hours')),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'virtual',
            'meeting_requested', false,
            'name', 'Started Event',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    false,
    'Started event meeting disabled after being enabled returns false'
);

-- Started pending event remains out of sync
select is(
    is_event_meeting_in_sync(
        jsonb_build_object(
            'ends_at', floor(extract(epoch from current_timestamp - interval '1 hour')),
            'meeting_in_sync', false,
            'meeting_requested', true,
            'name', 'Started Pending Event',
            'starts_at', floor(extract(epoch from current_timestamp - interval '2 hours')),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'kind_id', 'virtual',
            'meeting_requested', true,
            'name', 'Started Pending Event Updated',
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    ),
    false,
    'Started pending event meeting stays out of sync'
);

-- Recording preference change desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_recording_requested": true,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_recording_requested": false,
            "meeting_requested": true
        }'::jsonb
    ),
    false,
    'Event recording preference change desyncs meeting'
);

-- meeting_hosts unchanged keeps sync
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb
    ),
    true,
    'Event meeting_hosts unchanged keeps sync'
);

-- meeting_hosts change desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb
    ),
    false,
    'Event meeting_hosts change desyncs meeting'
);

-- meeting_hosts added desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb
    ),
    false,
    'Event meeting_hosts added desyncs meeting'
);

-- Event hosts unchanged keeps sync
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true,
            "hosts": [{"user_id": "00000000-0000-0000-0000-000000000001"}]
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "hosts": ["00000000-0000-0000-0000-000000000001"]
        }'::jsonb
    ),
    true,
    'Event hosts unchanged keeps sync'
);

-- Event hosts change desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true,
            "hosts": [{"user_id": "00000000-0000-0000-0000-000000000001"}]
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "hosts": ["00000000-0000-0000-0000-000000000002"]
        }'::jsonb
    ),
    false,
    'Event hosts change desyncs meeting'
);

-- Event speakers unchanged keeps sync
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000001", "featured": false}]
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000001", "featured": false}]
        }'::jsonb
    ),
    true,
    'Event speakers unchanged keeps sync'
);

-- Event speakers change desyncs meeting
select is(
    is_event_meeting_in_sync(
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind": "virtual",
            "starts_at": 1748786400,
            "ends_at": 1748790000,
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000001", "featured": false}]
        }'::jsonb,
        '{
            "name": "Sync Event",
            "timezone": "America/New_York",
            "kind_id": "virtual",
            "starts_at": "2025-06-01T10:00:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000002", "featured": false}]
        }'::jsonb
    ),
    false,
    'Event speakers change desyncs meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
