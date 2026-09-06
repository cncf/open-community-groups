-- Tests payment job retry backoff.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should apply bounded exponential payment job retry delays
select results_eq(
    $$
        select attempt_count, payment_job_retry_delay(attempt_count)
        from (values
            (-1),
            (0),
            (1),
            (2),
            (5),
            (7),
            (10)
        ) as attempts(attempt_count)
        order by attempt_count
    $$,
    $$ values
        (-1, interval '1 minute'),
        (0, interval '1 minute'),
        (1, interval '1 minute'),
        (2, interval '2 minutes'),
        (5, interval '16 minutes'),
        (7, interval '30 minutes'),
        (10, interval '30 minutes')
    $$,
    'Should apply bounded exponential payment job retry delays'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
