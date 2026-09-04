-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep unconfigured registration windows open after the event starts
select ok(
    is_registration_window_open(
        null,
        null,
        current_timestamp - interval '1 hour'
    ),
    'Should keep unconfigured registration windows open after the event starts'
);

-- Should reject registration before the open date
select is(
    is_registration_window_open(
        current_timestamp + interval '1 hour',
        null,
        current_timestamp + interval '2 hours'
    ),
    false,
    'Should reject registration before the open date'
);

-- Should keep open-only registration windows open before the event starts
select ok(
    is_registration_window_open(
        current_timestamp - interval '2 hours',
        null,
        current_timestamp + interval '1 hour'
    ),
    'Should keep open-only registration windows open before the event starts'
);

-- Should close open-only registration windows at the event start
select is(
    is_registration_window_open(
        current_timestamp - interval '2 hours',
        null,
        current_timestamp - interval '1 hour'
    ),
    false,
    'Should close open-only registration windows at the event start'
);

-- Should keep open-only registration windows open for dateless events
select ok(
    is_registration_window_open(
        current_timestamp - interval '2 hours',
        null,
        null
    ),
    'Should keep open-only registration windows open for dateless events'
);

-- Should keep registration windows open before the close date
select ok(
    is_registration_window_open(
        null,
        current_timestamp + interval '1 hour',
        current_timestamp + interval '2 hours'
    ),
    'Should keep registration windows open before the close date'
);

-- Should close registration windows after the close date
select is(
    is_registration_window_open(
        null,
        current_timestamp - interval '1 hour',
        current_timestamp + interval '2 hours'
    ),
    false,
    'Should close registration windows after the close date'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
