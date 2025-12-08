-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all session kinds ordered by session_kind_id
select is(
    list_session_kinds()::jsonb,
    '[
        {
            "session_kind_id": "hybrid",
            "display_name": "Hybrid"
        },
        {
            "session_kind_id": "in-person",
            "display_name": "In-Person"
        },
        {
            "session_kind_id": "virtual",
            "display_name": "Virtual"
        }
    ]'::jsonb,
    'Should return all session kinds ordered by session_kind_id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
