-- Tests building dense daily count series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fill missing days with zeros between the bounds
select is(
    stats_day_count_series(
        '2030-01-01'::date,
        '2030-01-04'::date,
        '[
            {"day": "2030-01-02", "count": 3},
            {"day": "2030-01-04", "count": 1}
        ]'::jsonb
    )::jsonb,
    '[
        ["2030-01-01", 0],
        ["2030-01-02", 3],
        ["2030-01-03", 0],
        ["2030-01-04", 1]
    ]'::jsonb,
    'Should fill missing days with zeros between the bounds'
);

-- Should return a single day series with its count
select is(
    stats_day_count_series(
        '2030-01-01'::date,
        '2030-01-01'::date,
        '[{"day": "2030-01-01", "count": 5}]'::jsonb
    )::jsonb,
    '[["2030-01-01", 5]]'::jsonb,
    'Should return a single day series with its count'
);

-- Should return a single zero day for null counts
select is(
    stats_day_count_series('2030-01-01'::date, '2030-01-01'::date, null)::jsonb,
    '[["2030-01-01", 0]]'::jsonb,
    'Should return a single zero day for null counts'
);

-- Should return an empty series for null bounds
select is(
    stats_day_count_series(null, null, '[{"day": "2030-01-02", "count": 3}]'::jsonb)::jsonb,
    '[]'::jsonb,
    'Should return an empty series for null bounds'
);

-- Should return an empty series when the start is after the end
select is(
    stats_day_count_series('2030-01-04'::date, '2030-01-01'::date, null)::jsonb,
    '[]'::jsonb,
    'Should return an empty series when the start is after the end'
);

-- Should sum repeated days and ignore days outside the bounds
select is(
    stats_day_count_series(
        '2030-01-01'::date,
        '2030-01-02'::date,
        '[
            {"day": "2030-01-01", "count": 2},
            {"day": "2030-01-01", "count": 4},
            {"day": "2030-01-05", "count": 9}
        ]'::jsonb
    )::jsonb,
    '[
        ["2030-01-01", 6],
        ["2030-01-02", 0]
    ]'::jsonb,
    'Should sum repeated days and ignore days outside the bounds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
