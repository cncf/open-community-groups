-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an omitted CFS labels payload
select lives_ok(
    $$select validate_event_cfs_labels_payload(null)$$,
    'Should accept an omitted CFS labels payload'
);

-- Should accept distinct CFS label names
select lives_ok(
    $$select validate_event_cfs_labels_payload(
        '[
            {"name": "Track / Backend", "color": "#DBEAFE"},
            {"name": "Track / Frontend", "color": "#FEE2E2"}
        ]'::jsonb
    )$$,
    'Should accept distinct CFS label names'
);

-- Should reject duplicate CFS label names
select throws_ok(
    $$select validate_event_cfs_labels_payload(
        '[
            {"name": "Track / Backend", "color": "#DBEAFE"},
            {"name": "Track / Backend", "color": "#FEE2E2"}
        ]'::jsonb
    )$$,
    'duplicate cfs label names',
    'Should reject duplicate CFS label names'
);

-- Should reject more than 200 CFS labels
select throws_ok(
    $$select validate_event_cfs_labels_payload(
        (
            select jsonb_agg(
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'name', 'Label ' || gs
                )
            )
            from generate_series(1, 201) as gs
        )
    )$$,
    'too many cfs labels',
    'Should reject more than 200 CFS labels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
