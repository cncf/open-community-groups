-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list session proposal levels
select is(
    list_session_proposal_levels()::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'display_name',
            'Advanced',
            'session_proposal_level_id',
            'advanced'
        ),
        jsonb_build_object(
            'display_name',
            'Beginner',
            'session_proposal_level_id',
            'beginner'
        ),
        jsonb_build_object(
            'display_name',
            'Intermediate',
            'session_proposal_level_id',
            'intermediate'
        )
    ),
    'Should list session proposal levels'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
