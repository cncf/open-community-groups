-- Tests building a page views block from daily view totals.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return empty series and zero total views for null input
select is(
    stats_page_views(null, null, '2025-01-01'::date, '2025-03-01'::date)::jsonb,
    '{"per_day_views": [], "per_month_views": [], "total_views": 0}'::jsonb,
    'Should return empty series and zero total views for null input'
);

-- Should exclude a day before the recent start from per_day_views only
select is(
    stats_page_views(
        array['2025-02-28', '2025-03-01']::date[],
        array[2, 3],
        '2025-01-01'::date,
        '2025-03-01'::date
    )::jsonb,
    '{
        "per_day_views": [["2025-03-01", 3]],
        "per_month_views": [["2025-02", 2], ["2025-03", 3]],
        "total_views": 5
    }'::jsonb,
    'Should exclude a day before the recent start from per_day_views only'
);

-- Should exclude a day before the period start from per_month_views while counting it in total_views
select is(
    stats_page_views(
        array['2024-12-31', '2025-01-01']::date[],
        array[4, 1],
        '2025-01-01'::date,
        '2025-03-01'::date
    )::jsonb,
    '{
        "per_day_views": [],
        "per_month_views": [["2025-01", 1]],
        "total_views": 5
    }'::jsonb,
    'Should exclude a day before the period start from per_month_views while counting it in total_views'
);

-- Should sum rows of the same day and month and order both series by label
select is(
    stats_page_views(
        array['2025-03-02', '2025-03-01', '2025-03-02', '2025-02-10']::date[],
        array[1, 2, 3, 4],
        '2025-01-01'::date,
        '2025-03-01'::date
    )::jsonb,
    '{
        "per_day_views": [["2025-03-01", 2], ["2025-03-02", 4]],
        "per_month_views": [["2025-02", 4], ["2025-03", 6]],
        "total_views": 10
    }'::jsonb,
    'Should sum rows of the same day and month and order both series by label'
);

-- Should sum concatenated arrays of several scopes like a single scope
select is(
    stats_page_views(
        array['2025-03-01']::date[] || array['2025-03-01', '2025-03-03']::date[],
        array[2] || array[5, 1],
        '2025-01-01'::date,
        '2025-03-01'::date
    )::jsonb,
    '{
        "per_day_views": [["2025-03-01", 7], ["2025-03-03", 1]],
        "per_month_views": [["2025-03", 8]],
        "total_views": 8
    }'::jsonb,
    'Should sum concatenated arrays of several scopes like a single scope'
);

-- Should label both series from the stored day under a non-UTC session time zone
set local time zone 'America/New_York';
select is(
    stats_page_views(
        array['2025-02-01']::date[],
        array[1],
        '2025-01-01'::date,
        '2025-01-01'::date
    )::jsonb,
    '{
        "per_day_views": [["2025-02-01", 1]],
        "per_month_views": [["2025-02", 1]],
        "total_views": 1
    }'::jsonb,
    'Should label both series from the stored day under a non-UTC session time zone'
);

-- Restore the session time zone
set local time zone default;

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
