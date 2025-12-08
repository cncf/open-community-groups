-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- TESTS
-- ============================================================================

-- All fields remain in sync so meeting_in_sync stays true
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session all fields in sync returns true'
);

-- Meeting disabled after being enabled returns false to trigger deletion
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": false
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting disabled after being enabled returns false'
);

-- Re-enabling meeting after it was disabled desyncs meeting_in_sync
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": false
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting re-enabled after disable desyncs meeting'
);

-- Missing meeting_requested with previously enabled meeting returns false
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00"
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting requested missing with previous enabled returns false'
);

-- Name change causes meeting to be out of sync
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One Updated",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session name change desyncs meeting'
);

-- Schedule change (start or end) desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:30:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session schedule change desyncs meeting'
);

-- Event timezone change desyncs session meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/Chicago"}'::jsonb
    ),
    false,
    'Event timezone change desyncs session meeting'
);

-- Kind change from hybrid to in-person desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "hybrid",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "in-person",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session kind change from hybrid to in-person desyncs meeting'
);

-- Kind change from virtual to in-person desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "in-person",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session kind change from virtual to in-person desyncs meeting'
);

-- meeting_hosts unchanged keeps sync
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session meeting_hosts unchanged keeps sync'
);

-- meeting_hosts change desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting_hosts change desyncs meeting'
);

-- meeting_hosts added desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    false,
    'Session meeting_hosts added desyncs meeting'
);

-- Event hosts unchanged keeps sync
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York", "hosts": [{"user_id": "00000000-0000-0000-0000-000000000001"}]}'::jsonb,
        '{"timezone": "America/New_York", "hosts": ["00000000-0000-0000-0000-000000000001"]}'::jsonb
    ),
    true,
    'Event hosts unchanged keeps session sync'
);

-- Event hosts change desyncs session meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true
        }'::jsonb,
        '{"timezone": "America/New_York", "hosts": [{"user_id": "00000000-0000-0000-0000-000000000001"}]}'::jsonb,
        '{"timezone": "America/New_York", "hosts": ["00000000-0000-0000-0000-000000000002"]}'::jsonb
    ),
    false,
    'Event hosts change desyncs session meeting'
);

-- Session speakers unchanged keeps sync
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000001", "featured": false}]
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000001", "featured": false}]
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb
    ),
    true,
    'Session speakers unchanged keeps sync'
);

-- Session speakers change desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000001", "featured": false}]
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "speakers": [{"user_id": "00000000-0000-0000-0000-000000000002", "featured": false}]
        }'::jsonb,
        '{"timezone": "America/New_York"}'::jsonb,
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
