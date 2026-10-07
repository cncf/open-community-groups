-- Tests validating the labels payload of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an empty labels payload
select lives_ok(
    $$select validate_event_labels_payload('[]'::jsonb)$$,
    'Should accept an empty labels payload'
);

-- Should accept labels with distinct identifiers and names
select lives_ok(
    $$select validate_event_labels_payload(
        '[
            {"color": "#DBEAFE", "event_label_id": "1abe3000-0000-0000-0000-000000000001", "name": "Track / Backend"},
            {"color": "#FEE2E2", "event_label_id": "1abe3000-0000-0000-0000-000000000002", "is_new": true, "name": "Track / Frontend"}
        ]'::jsonb
    )$$,
    'Should accept labels with distinct identifiers and names'
);

-- Should reject a labels payload that is not an array
select throws_ok(
    $$select validate_event_labels_payload('{"name": "Track / Backend"}'::jsonb)$$,
    'OCG01',
    'invalid label payload',
    'Should reject a labels payload that is not an array'
);

-- Should reject a null labels payload
select throws_ok(
    $$select validate_event_labels_payload(null)$$,
    'OCG01',
    'invalid label payload',
    'Should reject a null labels payload'
);

-- Should reject duplicate label identifiers
select throws_ok(
    $$select validate_event_labels_payload(
        '[
            {"color": "#DBEAFE", "event_label_id": "1abe3000-0000-0000-0000-000000000001", "name": "Track / Backend"},
            {"color": "#FEE2E2", "event_label_id": "1abe3000-0000-0000-0000-000000000001", "name": "Track / Frontend"}
        ]'::jsonb
    )$$,
    'OCG01',
    'duplicate label ids',
    'Should reject duplicate label identifiers'
);

-- Should reject duplicate label names
select throws_ok(
    $$select validate_event_labels_payload(
        '[
            {"color": "#DBEAFE", "event_label_id": "1abe3000-0000-0000-0000-000000000001", "name": "Track / Backend"},
            {"color": "#FEE2E2", "event_label_id": "1abe3000-0000-0000-0000-000000000002", "name": "Track / Backend"}
        ]'::jsonb
    )$$,
    'OCG01',
    'duplicate label names',
    'Should reject duplicate label names'
);

-- Should reject label entries that are not objects
select throws_ok(
    $$select validate_event_labels_payload('["Track / Backend"]'::jsonb)$$,
    'OCG01',
    'invalid label payload',
    'Should reject label entries that are not objects'
);

-- Should reject label names that are duplicates after trimming
select throws_ok(
    $$select validate_event_labels_payload(
        '[
            {"color": "#DBEAFE", "event_label_id": "1abe3000-0000-0000-0000-000000000001", "name": "Track / Backend"},
            {"color": "#FEE2E2", "event_label_id": "1abe3000-0000-0000-0000-000000000002", "name": "  Track / Backend  "}
        ]'::jsonb
    )$$,
    'OCG01',
    'duplicate label names',
    'Should reject label names that are duplicates after trimming'
);

-- Should reject labels with a blank identifier
select throws_ok(
    $$select validate_event_labels_payload(
        '[{"color": "#DBEAFE", "event_label_id": "", "name": "Track / Backend"}]'::jsonb
    )$$,
    'OCG01',
    'invalid label payload',
    'Should reject labels with a blank identifier'
);

-- Should reject labels with a whitespace-only name
select throws_ok(
    $$select validate_event_labels_payload(
        '[{"color": "#DBEAFE", "event_label_id": "1abe3000-0000-0000-0000-000000000001", "name": "   "}]'::jsonb
    )$$,
    'OCG01',
    'invalid label payload',
    'Should reject labels with a whitespace-only name'
);

-- Should reject labels without a name
select throws_ok(
    $$select validate_event_labels_payload(
        '[{"color": "#DBEAFE", "event_label_id": "1abe3000-0000-0000-0000-000000000001"}]'::jsonb
    )$$,
    'OCG01',
    'invalid label payload',
    'Should reject labels without a name'
);

-- Should reject labels without an identifier
select throws_ok(
    $$select validate_event_labels_payload(
        '[{"color": "#DBEAFE", "name": "Track / Backend"}]'::jsonb
    )$$,
    'OCG01',
    'invalid label payload',
    'Should reject labels without an identifier'
);

-- Should reject more than 200 labels
select throws_ok(
    $$select validate_event_labels_payload(
        (
            select jsonb_agg(
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'event_label_id', gen_random_uuid(),
                    'name', 'Label ' || gs
                )
            )
            from generate_series(1, 201) as gs
        )
    )$$,
    'OCG01',
    'too many labels',
    'Should reject more than 200 labels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
