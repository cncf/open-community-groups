-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

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
