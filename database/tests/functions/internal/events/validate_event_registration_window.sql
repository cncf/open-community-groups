-- Tests validating event registration windows against the event start.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a registration window that closes at the event start
select lives_ok(
    $$select validate_event_registration_window(
        '2030-01-01 09:00:00+00'::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz
    )$$,
    'Should accept a registration window that closes at the event start'
);

-- Should accept a registration window that opens at the event start
select lives_ok(
    $$select validate_event_registration_window(
        '2030-01-02 10:00:00+00'::timestamptz,
        null::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz
    )$$,
    'Should accept a registration window that opens at the event start'
);

-- Should accept registration bounds when the event has no start date
select lives_ok(
    $$select validate_event_registration_window(
        '2030-01-01 09:00:00+00'::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz,
        null::timestamptz
    )$$,
    'Should accept registration bounds when the event has no start date'
);

-- Should reject open-only registration windows that open after the event start
select throws_ok(
    $$select validate_event_registration_window(
        '2030-01-02 10:00:01+00'::timestamptz,
        null::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz
    )$$,
    'OCG01',
    'registration starts_at cannot be after event starts_at',
    'Should reject open-only registration windows that open after the event start'
);

-- Should reject registration close dates after the event start
select throws_ok(
    $$select validate_event_registration_window(
        null::timestamptz,
        '2030-01-02 10:00:01+00'::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz
    )$$,
    'OCG01',
    'registration ends_at cannot be after event starts_at',
    'Should reject registration close dates after the event start'
);

-- Should reject registration windows where the open date equals the close date
select throws_ok(
    $$select validate_event_registration_window(
        '2030-01-01 09:00:00+00'::timestamptz,
        '2030-01-01 09:00:00+00'::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz
    )$$,
    'OCG01',
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date equals the close date'
);

-- Should reject registration windows where the open date is after the close date
select throws_ok(
    $$select validate_event_registration_window(
        '2030-01-01 10:00:00+00'::timestamptz,
        '2030-01-01 09:00:00+00'::timestamptz,
        '2030-01-02 10:00:00+00'::timestamptz
    )$$,
    'OCG01',
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date is after the close date'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
