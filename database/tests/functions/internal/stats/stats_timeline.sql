-- Tests building the count timeline of a stats domain from monthly buckets.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count a null bucket only toward the total
select is(
    stats_timeline('[
        {"bucket_start": null, "count": 2, "in_period": null},
        {"bucket_start": "2025-01-01T00:00:00Z", "count": 1, "in_period": true}
    ]'::jsonb, false)::jsonb,
    '{
        "per_month": [["2025-01", 1]],
        "running_total": [[1735689600000, 1]],
        "total": 3
    }'::jsonb,
    'Should count a null bucket only toward the total'
);

-- Should count only the in-period part of a split month in per_month and sum it into one running total point
select is(
    stats_timeline('[
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 2, "in_period": false},
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 3, "in_period": true}
    ]'::jsonb, false)::jsonb,
    '{
        "per_month": [["2025-02", 3]],
        "running_total": [[1738368000000, 5]],
        "total": 5
    }'::jsonb,
    'Should count only the in-period part of a split month in per_month and sum it into one running total point'
);

-- Should count only the in-period part of a split month in a running total from the period
select is(
    stats_timeline('[
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 2, "in_period": false},
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 3, "in_period": true}
    ]'::jsonb, true)::jsonb,
    '{
        "per_month": [["2025-02", 3]],
        "running_total": [[1738368000000, 3]],
        "total": 5
    }'::jsonb,
    'Should count only the in-period part of a split month in a running total from the period'
);

-- Should exclude out-of-period rows from a running total from the period while counting them in the total
select is(
    stats_timeline('[
        {"bucket_start": "2025-01-01T00:00:00Z", "count": 4, "in_period": false},
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 1, "in_period": true}
    ]'::jsonb, true)::jsonb,
    '{
        "per_month": [["2025-02", 1]],
        "running_total": [[1738368000000, 1]],
        "total": 5
    }'::jsonb,
    'Should exclude out-of-period rows from a running total from the period while counting them in the total'
);

-- Should order both series by month and accumulate the running total
select is(
    stats_timeline('[
        {"bucket_start": "2025-03-01T00:00:00Z", "count": 3, "in_period": true},
        {"bucket_start": "2025-01-01T00:00:00Z", "count": 1, "in_period": true},
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 2, "in_period": true}
    ]'::jsonb, false)::jsonb,
    '{
        "per_month": [["2025-01", 1], ["2025-02", 2], ["2025-03", 3]],
        "running_total": [
            [1735689600000, 1],
            [1738368000000, 3],
            [1740787200000, 6]
        ],
        "total": 6
    }'::jsonb,
    'Should order both series by month and accumulate the running total'
);

-- Should label per_month from the UTC bucket month under a non-UTC session time zone
set local time zone 'America/New_York';
select is(
    stats_timeline('[
        {"bucket_start": "2025-02-01T00:00:00Z", "count": 1, "in_period": true}
    ]'::jsonb, false)::jsonb,
    '{
        "per_month": [["2025-02", 1]],
        "running_total": [[1738368000000, 1]],
        "total": 1
    }'::jsonb,
    'Should label per_month from the UTC bucket month under a non-UTC session time zone'
);

-- Restore the session time zone for the remaining scenarios
set local time zone default;

-- Should return empty series and a zero total for null input
select is(
    stats_timeline(null, false)::jsonb,
    '{"per_month": [], "running_total": [], "total": 0}'::jsonb,
    'Should return empty series and a zero total for null input'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
