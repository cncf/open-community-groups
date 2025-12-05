-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": true,
            "meeting_requires_password": false
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": false,
            "meeting_requires_password": false
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": false,
            "meeting_requires_password": false
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One Updated",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
    ),
    false,
    'Session name change desyncs meeting'
);

-- Password requirement change desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": false
        }'::jsonb,
        'America/New_York',
        'America/New_York'
    ),
    false,
    'Session password change desyncs meeting'
);

-- Schedule change (start or end) desyncs meeting
select is(
    is_session_meeting_in_sync(
        '{
            "name": "Session One",
            "session_kind_id": "virtual",
            "starts_at": 1748787300,
            "ends_at": 1748789100,
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:30:00",
            "ends_at": "2025-06-01T11:00:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/Chicago'
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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "in-person",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "in-person",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requires_password": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requires_password": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true,
            "meeting_hosts": ["host1@example.com", "host2@example.com"]
        }'::jsonb,
        'America/New_York',
        'America/New_York'
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
            "meeting_requested": true,
            "meeting_requires_password": true
        }'::jsonb,
        '{
            "name": "Session One",
            "kind": "virtual",
            "starts_at": "2025-06-01T10:15:00",
            "ends_at": "2025-06-01T10:45:00",
            "meeting_requested": true,
            "meeting_requires_password": true,
            "meeting_hosts": ["host1@example.com"]
        }'::jsonb,
        'America/New_York',
        'America/New_York'
    ),
    false,
    'Session meeting_hosts added desyncs meeting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
