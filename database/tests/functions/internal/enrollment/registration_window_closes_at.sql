-- Tests resolving when an event registration window closes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should close at the event start when only the registration start is set
select is(
    registration_window_closes_at(
        '2030-01-01 00:00+00'::timestamptz,
        null::timestamptz,
        '2030-02-01 00:00+00'::timestamptz
    ),
    '2030-02-01 00:00+00'::timestamptz,
    'Should close at the event start when only the registration start is set'
);

-- Should close at the registration end when every bound is set
select is(
    registration_window_closes_at(
        '2030-01-01 00:00+00'::timestamptz,
        '2030-01-20 00:00+00'::timestamptz,
        '2030-02-01 00:00+00'::timestamptz
    ),
    '2030-01-20 00:00+00'::timestamptz,
    'Should close at the registration end when every bound is set'
);

-- Should close at the registration end when the event is undated
select is(
    registration_window_closes_at(
        '2030-01-01 00:00+00'::timestamptz,
        '2030-01-20 00:00+00'::timestamptz,
        null::timestamptz
    ),
    '2030-01-20 00:00+00'::timestamptz,
    'Should close at the registration end when the event is undated'
);

-- Should close at the registration end without a registration start
select is(
    registration_window_closes_at(
        null::timestamptz,
        '2030-01-20 00:00+00'::timestamptz,
        '2030-02-01 00:00+00'::timestamptz
    ),
    '2030-01-20 00:00+00'::timestamptz,
    'Should close at the registration end without a registration start'
);

-- Should close at the registration end without other bounds
select is(
    registration_window_closes_at(
        null::timestamptz,
        '2030-01-20 00:00+00'::timestamptz,
        null::timestamptz
    ),
    '2030-01-20 00:00+00'::timestamptz,
    'Should close at the registration end without other bounds'
);

-- Should keep the registration end when it is later than the event start
select is(
    registration_window_closes_at(
        '2030-01-01 00:00+00'::timestamptz,
        '2030-02-10 00:00+00'::timestamptz,
        '2030-02-01 00:00+00'::timestamptz
    ),
    '2030-02-10 00:00+00'::timestamptz,
    'Should keep the registration end when it is later than the event start'
);

-- Should never close when only the event start is set
select is(
    registration_window_closes_at(
        null::timestamptz,
        null::timestamptz,
        '2030-02-01 00:00+00'::timestamptz
    ),
    null::timestamptz,
    'Should never close when only the event start is set'
);

-- Should never close when only the registration start is set for an undated event
select is(
    registration_window_closes_at(
        '2030-01-01 00:00+00'::timestamptz,
        null::timestamptz,
        null::timestamptz
    ),
    null::timestamptz,
    'Should never close when only the registration start is set for an undated event'
);

-- Should never close without any bound
select is(
    registration_window_closes_at(
        null::timestamptz,
        null::timestamptz,
        null::timestamptz
    ),
    null::timestamptz,
    'Should never close without any bound'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
