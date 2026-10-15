-- Tests validating automatic meeting durations against provider limits.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingLimits '{"zoom": {"max_duration_minutes": 720, "max_participants": 100, "min_duration_minutes": 5}}'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an event meeting lasting the maximum duration
select lives_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-01T22:00:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'Should accept an event meeting lasting the maximum duration'
);

-- Should accept an event meeting lasting the minimum duration
select lives_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-01T10:05:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'Should accept an event meeting lasting the minimum duration'
);

-- Should ignore durations when no meeting limits are configured
select lives_ok(
    $$select validate_event_meeting_durations(
        '{"ends_at": "2030-03-02T10:00:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
        null
    )$$,
    'Should ignore durations when no meeting limits are configured'
);

-- Should ignore events and sessions without a requested meeting
select lives_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-02T10:00:00", "meeting_requested": false, "sessions": [{"ends_at": "2030-03-02T09:00:00", "meeting_requested": false, "name": "Workshop", "starts_at": "2030-03-01T10:00:00"}], "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'Should ignore events and sessions without a requested meeting'
);

-- Should measure durations in the payload timezone across daylight saving changes
select lives_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-31T07:00:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-30T18:00:00", "timezone": "Europe/Madrid"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'Should measure durations in the payload timezone across daylight saving changes'
);

-- Should reject a session meeting longer than the maximum duration
select throws_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-02T10:00:00", "meeting_requested": false, "sessions": [{"ends_at": "2030-03-01T23:00:00", "meeting_provider_id": "zoom", "meeting_requested": true, "name": "Workshop", "starts_at": "2030-03-01T10:00:00"}], "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'OCG01',
    'session "Workshop" meeting duration (780 minutes) must be between 5 and 720 minutes',
    'Should reject a session meeting longer than the maximum duration'
);

-- Should reject an event meeting longer than the maximum duration
select throws_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-01T22:01:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'OCG01',
    'event meeting duration (721 minutes) must be between 5 and 720 minutes',
    'Should reject an event meeting longer than the maximum duration'
);

-- Should reject an event meeting shorter than the minimum duration
select throws_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"ends_at": "2030-03-01T10:04:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'OCG01',
    'event meeting duration (4 minutes) must be between 5 and 720 minutes',
    'Should reject an event meeting shorter than the minimum duration'
);

-- Should skip meetings for providers without configured limits
select lives_ok(
    $$select validate_event_meeting_durations(
        '{"ends_at": "2030-03-02T10:00:00", "meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
        '{"other": {"max_duration_minutes": 720, "max_participants": 100, "min_duration_minutes": 5}}'::jsonb
    )$$,
    'Should skip meetings for providers without configured limits'
);

-- Should skip meetings without both schedule dates
select lives_ok(
    format(
        $$select validate_event_meeting_durations(
            '{"meeting_provider_id": "zoom", "meeting_requested": true, "starts_at": "2030-03-01T10:00:00", "timezone": "UTC"}'::jsonb,
            %L::jsonb
        )$$,
        :'meetingLimits'
    ),
    'Should skip meetings without both schedule dates'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
