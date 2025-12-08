-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all three event kinds ordered by event_kind_id
select is(
    list_event_kinds()::jsonb,
    '[
        {
            "event_kind_id": "hybrid",
            "display_name": "Hybrid"
        },
        {
            "event_kind_id": "in-person",
            "display_name": "In Person"
        },
        {
            "event_kind_id": "virtual",
            "display_name": "Virtual"
        }
    ]'::jsonb,
    'Should return all three event kinds ordered by event_kind_id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
