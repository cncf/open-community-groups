-- Tests encoding timestamps as whole epoch seconds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return whole seconds for exact timestamps
select is(
    epoch_seconds('2024-01-01 00:00:00+00'::timestamptz),
    1704067200::bigint,
    'Should return whole seconds for exact timestamps'
);

-- Should truncate fractional seconds instead of rounding
select is(
    epoch_seconds('2024-01-01 00:00:00.9+00'::timestamptz),
    1704067200::bigint,
    'Should truncate fractional seconds instead of rounding'
);

-- Should return null for null timestamps
select is(
    epoch_seconds(null),
    null::bigint,
    'Should return null for null timestamps'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
