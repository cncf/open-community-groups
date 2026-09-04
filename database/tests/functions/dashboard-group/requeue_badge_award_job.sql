-- Tests operator requeueing of failed badge award jobs.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b3060000-0000-0000-0000-000000000001'
\set failedJobID 'b3060000-0000-0000-0000-000000000002'
\set groupCategoryID 'b3060000-0000-0000-0000-000000000003'
\set groupID 'b3060000-0000-0000-0000-000000000004'
\set pendingJobID 'b3060000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Failed and pending jobs used by requeue scenarios
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    badge_snapshot,
    community_id,
    completed_at,
    error,
    failure_count,
    group_id,
    recipient_count,
    status
) values
    (:'failedJobID', 1, 'requeue-admin', '{"name":"Failed"}', :'communityID', current_timestamp - interval '1 day', 'provider outage', 3, :'groupID', 1, 'failed'),
    (:'pendingJobID', 1, 'requeue-admin', '{"name":"Pending"}', :'communityID', null, null, 0, :'groupID', 1, 'pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a missing badge award job
select throws_ok(
    $$select requeue_badge_award_job(gen_random_uuid())$$,
    'failed badge award job not found',
    'Should reject a missing badge award job'
);

-- Should reject a non-failed badge award job
select throws_ok(
    format($$select requeue_badge_award_job(%L::uuid)$$, :'pendingJobID'),
    'failed badge award job not found',
    'Should reject a non-failed badge award job'
);

-- Should requeue an operator-reviewed failed badge award job
select lives_ok(
    format($$select requeue_badge_award_job(%L::uuid)$$, :'failedJobID'),
    'Should requeue an operator-reviewed failed badge award job'
);

-- Should reset failed job retry state
select ok(
    (
        select status = 'pending'
            and completed_at is null
            and error is null
            and failure_count = 0
            and next_attempt_at = current_timestamp
        from badge_award_job
        where badge_award_job_id = :'failedJobID'
    ),
    'Should reset failed job retry state'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
