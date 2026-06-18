-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a future event that stays in the future
select lives_ok(
    $$select validate_update_event_dates(
        '{
            "starts_at": "2030-01-01T10:00:00",
            "ends_at": "2030-01-01T11:00:00",
            "timezone": "UTC"
        }'::jsonb,
        '{
            "starts_at": 1893492000,
            "ends_at": 1893495600
        }'::jsonb
    )$$,
    'Should accept a future event that stays in the future'
);

-- Should reject a future event that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '1 day'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '1 day' + interval '1 hour'))::bigint
        )
    )$$,
    'event starts_at cannot be in the past',
    'Should reject a future event that moves into the past'
);

-- Should reject registration windows where the open date is after the close date
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '4 days'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '4 days' + interval '1 hour'))::bigint
        )
    )$$,
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date is after the close date'
);

-- Should reject registration windows where the open date equals the close date
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '4 days'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '4 days' + interval '1 hour'))::bigint
        )
    )$$,
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date equals the close date'
);

-- Should reject registration close dates after the event start
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '4 days'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '4 days' + interval '1 hour'))::bigint
        )
    )$$,
    'registration ends_at cannot be after event starts_at',
    'Should reject registration close dates after the event start'
);

-- Should reject open-only registration windows that open after the event start
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '4 days'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '4 days' + interval '1 hour'))::bigint
        )
    )$$,
    'registration starts_at cannot be after event starts_at',
    'Should reject open-only registration windows that open after the event start'
);

-- Should reject a past event that moves into the future
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp - interval '2 day'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp - interval '1 day'))::bigint
        )
    )$$,
    'event starts_at cannot be in the future',
    'Should reject a past event that moves into the future'
);

-- Should reject a live event that moves earlier than its current start
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp - interval '1 hour'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '1 hour'))::bigint
        )
    )$$,
    'event starts_at cannot be earlier than current value',
    'Should reject a live event that moves earlier than its current start'
);

-- Should reject a dateless event that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        '{}'::jsonb
    )$$,
    'event starts_at cannot be in the past',
    'Should reject a dateless event that moves into the past'
);

-- Should accept a dateless event that moves into the future
select lives_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day' + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        '{}'::jsonb
    )$$,
    'Should accept a dateless event that moves into the future'
);

-- Should reject a future session that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS')
                )
            )
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '1 day'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '1 day' + interval '1 hour'))::bigint
        )
    )$$,
    'session starts_at cannot be in the past',
    'Should reject a future session that moves into the past'
);

-- Should accept a live event update when a session keeps its current past dates
select lives_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'session_id', '3a4a0000-0000-0000-0000-000000000001',
                    'starts_at', to_char(
                        current_timestamp at time zone 'UTC' - interval '45 minutes',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    ),
                    'ends_at', to_char(
                        current_timestamp at time zone 'UTC' - interval '15 minutes',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    )
                )
            )
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp - interval '1 hour'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '2 hours'))::bigint,
            'sessions', jsonb_build_object(
                to_char(current_timestamp at time zone 'UTC', 'YYYY-MM-DD'),
                jsonb_build_array(
                    jsonb_build_object(
                        'session_id', '3a4a0000-0000-0000-0000-000000000001',
                        'starts_at', floor(extract(epoch from current_timestamp - interval '45 minutes'))::bigint,
                        'ends_at', floor(extract(epoch from current_timestamp - interval '15 minutes'))::bigint
                    )
                )
            )
        )
    )$$,
    'Should accept a live event update when a session keeps its current past dates'
);

-- Should reject a non-UTC future event that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(
                current_timestamp at time zone 'Asia/Kolkata' - interval '1 hour',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'timezone', 'Asia/Kolkata'
        ),
        jsonb_build_object(
            'starts_at', floor(extract(epoch from current_timestamp + interval '1 day'))::bigint,
            'ends_at', floor(extract(epoch from current_timestamp + interval '1 day' + interval '1 hour'))::bigint
        )
    )$$,
    'event starts_at cannot be in the past',
    'Should reject a non-UTC future event that moves into the past'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
