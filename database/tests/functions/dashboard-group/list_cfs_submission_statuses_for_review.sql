-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list CFS submission statuses for review
select is(
    list_cfs_submission_statuses_for_review()::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'cfs_submission_status_id',
            'approved',
            'display_name',
            'Approved'
        ),
        jsonb_build_object(
            'cfs_submission_status_id',
            'information-requested',
            'display_name',
            'Information requested'
        ),
        jsonb_build_object(
            'cfs_submission_status_id',
            'not-reviewed',
            'display_name',
            'Not reviewed'
        ),
        jsonb_build_object(
            'cfs_submission_status_id',
            'rejected',
            'display_name',
            'Rejected'
        )
    ),
    'Should list CFS submission statuses for review'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
