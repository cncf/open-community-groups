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
    stats_label_count_series_by_name(null)::jsonb,
    '{}'::jsonb,
    'Should return an empty JSON object for null input'
);

-- Should return an empty JSON object for empty input
select is(
    stats_label_count_series_by_name('[]'::jsonb)::jsonb,
    '{}'::jsonb,
    'Should return an empty JSON object for empty input'
);

-- Should return named label series ordered by name and label
select is(
    stats_label_count_series_by_name('[
        {"series_name": "Beta", "label": "2025-02", "count": 4},
        {"series_name": "Alpha", "label": "2025-03", "count": 3},
        {"series_name": "Alpha", "label": "2025-01", "count": 1}
    ]'::jsonb)::jsonb,
    '{
        "Alpha": [["2025-01", 1], ["2025-03", 3]],
        "Beta": [["2025-02", 4]]
    }'::jsonb,
    'Should return named label series ordered by name and label'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
