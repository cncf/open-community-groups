-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

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
