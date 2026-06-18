-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept future event and session dates
select lives_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day' + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day' + interval '15 minutes', 'YYYY-MM-DD"T"HH24:MI:SS'),
                    'ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day' + interval '45 minutes', 'YYYY-MM-DD"T"HH24:MI:SS')
                )
            )
        )
    )$$,
    'Should accept future event and session dates'
);

-- Should reject event starts_at in the past
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    )$$,
    'event starts_at cannot be in the past',
    'Should reject event starts_at in the past'
);

-- Should reject event ends_at in the past
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    )$$,
    'event ends_at cannot be in the past',
    'Should reject event ends_at in the past'
);

-- Should reject registration windows where the open date is after the close date
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    )$$,
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date is after the close date'
);

-- Should reject registration windows where the open date equals the close date
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    )$$,
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date equals the close date'
);

-- Should reject registration close dates after the event start
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    )$$,
    'registration ends_at cannot be after event starts_at',
    'Should reject registration close dates after the event start'
);

-- Should reject open-only registration windows that open after the event start
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        )
    )$$,
    'registration starts_at cannot be after event starts_at',
    'Should reject open-only registration windows that open after the event start'
);

-- Should reject session starts_at in the past
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS')
                )
            )
        )
    )$$,
    'session starts_at cannot be in the past',
    'Should reject session starts_at in the past'
);

-- Should reject session ends_at in the past
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
                    'ends_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS')
                )
            )
        )
    )$$,
    'session ends_at cannot be in the past',
    'Should reject session ends_at in the past'
);

-- Should validate dates using the event timezone
select throws_ok(
    $$select validate_add_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'Asia/Kolkata' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'Asia/Kolkata'
        )
    )$$,
    'event starts_at cannot be in the past',
    'Should validate dates using the event timezone'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
