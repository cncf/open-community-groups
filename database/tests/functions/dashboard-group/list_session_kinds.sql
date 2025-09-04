-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: list_session_kinds should return all session kinds
select is(
    list_session_kinds()::jsonb,
    '[
        {
            "session_kind_id": "in-person",
            "display_name": "In-Person"
        },
        {
            "session_kind_id": "virtual",
            "display_name": "Virtual"
        }
    ]'::jsonb,
    'list_session_kinds should return all session kinds ordered by session_kind_id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;

