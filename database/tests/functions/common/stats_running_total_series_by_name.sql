-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an empty JSON object for null input
select is(
    stats_running_total_series_by_name(null)::jsonb,
    '{}'::jsonb,
    'Should return an empty JSON object for null input'
);

-- Should return an empty JSON object for empty input
select is(
    stats_running_total_series_by_name('[]'::jsonb)::jsonb,
    '{}'::jsonb,
    'Should return an empty JSON object for empty input'
);

-- Should return named cumulative series ordered by name and bucket timestamp
select is(
    stats_running_total_series_by_name('[
        {"series_name": "Beta", "bucket_start": "2025-02-01T00:00:00Z", "count": 4},
        {"series_name": "Alpha", "bucket_start": "2025-03-01T00:00:00Z", "count": 3},
        {"series_name": "Alpha", "bucket_start": "2025-01-01T00:00:00Z", "count": 1}
    ]'::jsonb)::jsonb,
    '{
        "Alpha": [[1735689600000, 1], [1740787200000, 4]],
        "Beta": [[1738368000000, 4]]
    }'::jsonb,
    'Should return named cumulative series ordered by name and bucket timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
