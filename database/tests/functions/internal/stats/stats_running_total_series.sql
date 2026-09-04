-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an empty JSON array for null input
select is(
    stats_running_total_series(null)::jsonb,
    '[]'::jsonb,
    'Should return an empty JSON array for null input'
);

-- Should return an empty JSON array for empty input
select is(
    stats_running_total_series('[]'::jsonb)::jsonb,
    '[]'::jsonb,
    'Should return an empty JSON array for empty input'
);

-- Should return cumulative totals ordered by bucket timestamp
select is(
    stats_running_total_series('[
        {"bucket_start": "2025-03-01T00:00:00Z", "count": 3},
        {"bucket_start": "2025-01-01T00:00:00Z", "count": 1},
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 2}
    ]'::jsonb)::jsonb,
    '[
        [1735689600000, 1],
        [1738368000000, 3],
        [1740787200000, 6]
    ]'::jsonb,
    'Should return cumulative totals ordered by bucket timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
