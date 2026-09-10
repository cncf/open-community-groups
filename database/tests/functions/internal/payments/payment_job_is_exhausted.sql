-- Tests payment job exhaustion detection.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should require retryable status and the maximum attempt count
select results_eq(
    $$
        select status, attempt_count, payment_job_is_exhausted(
            jsonb_populate_record(null::payment_job, jsonb_build_object(
                'attempt_count', attempt_count,
                'status', status
            ))
        )
        from (values
            ('completed'::text, 10),
            ('failed'::text, 9),
            ('failed'::text, 10),
            ('pending'::text, 10),
            ('processing'::text, 10)
        ) as scenarios(status, attempt_count)
        order by status, attempt_count
    $$,
    $$ values
        ('completed'::text, 10, false),
        ('failed'::text, 9, false),
        ('failed'::text, 10, true),
        ('pending'::text, 10, true),
        ('processing'::text, 10, false)
    $$,
    'Should require retryable status and the maximum attempt count'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
