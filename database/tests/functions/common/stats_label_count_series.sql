-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an empty JSON array for null input
select is(
    stats_label_count_series(null)::jsonb,
    '[]'::jsonb,
    'Should return an empty JSON array for null input'
);

-- Should return an empty JSON array for empty input
select is(
    stats_label_count_series('[]'::jsonb)::jsonb,
    '[]'::jsonb,
    'Should return an empty JSON array for empty input'
);

-- Should return counts ordered by generic label
select is(
    stats_label_count_series('[
        {"label": "2025-03", "count": 3},
        {"label": "2025-01", "count": 1},
        {"label": "2025-02", "count": 2}
    ]'::jsonb)::jsonb,
    '[
        ["2025-01", 1],
        ["2025-02", 2],
        ["2025-03", 3]
    ]'::jsonb,
    'Should return counts ordered by generic label'
);

-- Should ignore extra fields when label and count are present
select is(
    stats_label_count_series('[
        {"label": "2025-01-03", "count": 3, "extra_label": "ignored", "extra_count": 30},
        {"label": "2025-01", "count": 1, "extra_label": "ignored", "extra_count": 10},
        {"label": "2025-01-02", "count": 2}
    ]'::jsonb)::jsonb,
    '[
        ["2025-01", 1],
        ["2025-01-02", 2],
        ["2025-01-03", 3]
    ]'::jsonb,
    'Should ignore extra fields when label and count are present'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
