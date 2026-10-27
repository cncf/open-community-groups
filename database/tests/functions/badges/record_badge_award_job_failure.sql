-- Tests recording badge award job processing failures.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set blankErrorClaimID 'b3040000-0000-0000-0000-000000000001'
\set blankErrorJobID 'b3040000-0000-0000-0000-000000000002'
\set cappedClaimID 'b3040000-0000-0000-0000-000000000003'
\set cappedJobID 'b3040000-0000-0000-0000-000000000004'
\set communityID 'b3040000-0000-0000-0000-000000000005'
\set groupCategoryID 'b3040000-0000-0000-0000-000000000006'
\set groupID 'b3040000-0000-0000-0000-000000000007'
\set retryClaimID 'b3040000-0000-0000-0000-000000000008'
\set retryJobID 'b3040000-0000-0000-0000-000000000009'
\set terminalClaimID 'b3040000-0000-0000-0000-00000000000a'
\set terminalJobID 'b3040000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Processing jobs used by blank error, capped backoff, retry and terminal failure scenarios
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    badge_snapshot,
    community_id,
    failure_count,
    group_id,
    next_attempt_at,
    recipient_count,
    status,

    claim_id,
    claimed_at
) values
    (:'blankErrorJobID', 1, 'failure-admin', '{"name":"Blank"}', :'communityID', 0, :'groupID', '2026-01-01 00:00:00+00', 1, 'processing', :'blankErrorClaimID', current_timestamp),
    (:'cappedJobID', 1, 'failure-admin', '{"name":"Capped"}', :'communityID', 5, :'groupID', '2026-01-01 00:00:00+00', 1, 'processing', :'cappedClaimID', current_timestamp),
    (:'retryJobID', 1, 'failure-admin', '{"name":"Retry"}', :'communityID', 0, :'groupID', '2026-01-01 00:00:00+00', 1, 'processing', :'retryClaimID', current_timestamp),
    (:'terminalJobID', 1, 'failure-admin', '{"name":"Terminal"}', :'communityID', 1, :'groupID', '2026-01-01 00:00:00+00', 1, 'processing', :'terminalClaimID', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a non-positive failure limit
select throws_ok(
    format(
        $$select record_badge_award_job_failure(%L::uuid, %L::uuid, 'bad limit', 0)$$,
        :'retryJobID', :'retryClaimID'
    ),
    'P0001',
    'badge award job failure limit must be positive',
    'Should reject a non-positive failure limit'
);

-- Should reject a missing processing claim
select throws_ok(
    format(
        $$select record_badge_award_job_failure(%L::uuid, gen_random_uuid(), 'missing claim', 10)$$,
        :'retryJobID'
    ),
    'P0001',
    'badge award job claim not found',
    'Should reject a missing processing claim'
);

-- Should schedule a retry before the failure limit
select is(
    record_badge_award_job_failure(:'retryJobID', :'retryClaimID', ' retry failure ', 10),
    false,
    'Should schedule a retry before the failure limit'
);

-- Should persist retry failure state with backoff
select results_eq(
    format(
        $$
            select claim_id, claimed_at, completed_at, error, failure_count, next_attempt_at, status
            from badge_award_job
            where badge_award_job_id = %L::uuid
        $$,
        :'retryJobID'
    ),
    $$ values (null::uuid, null::timestamptz, null::timestamptz, 'retry failure', 1, current_timestamp + interval '60 seconds', 'pending') $$,
    'Should persist retry failure state with backoff'
);

-- Should schedule a retry for a blank failure message
select is(
    record_badge_award_job_failure(:'blankErrorJobID', :'blankErrorClaimID', ' ', 10),
    false,
    'Should schedule a retry for a blank failure message'
);

-- Should store the default error for a blank failure message
select results_eq(
    format(
        $$
            select error, failure_count, next_attempt_at, status
            from badge_award_job
            where badge_award_job_id = %L::uuid
        $$,
        :'blankErrorJobID'
    ),
    $$ values ('badge award processing failed', 1, current_timestamp + interval '60 seconds', 'pending') $$,
    'Should store the default error for a blank failure message'
);

-- Should schedule a retry after repeated failures
select is(
    record_badge_award_job_failure(:'cappedJobID', :'cappedClaimID', 'capped failure', 10),
    false,
    'Should schedule a retry after repeated failures'
);

-- Should cap the retry backoff at thirty minutes
select results_eq(
    format(
        $$
            select error, failure_count, next_attempt_at, status
            from badge_award_job
            where badge_award_job_id = %L::uuid
        $$,
        :'cappedJobID'
    ),
    $$ values ('capped failure', 6, current_timestamp + interval '1800 seconds', 'pending') $$,
    'Should cap the retry backoff at thirty minutes'
);

-- Should terminally fail after the failure limit
select is(
    record_badge_award_job_failure(:'terminalJobID', :'terminalClaimID', 'terminal failure', 2),
    true,
    'Should terminally fail after the failure limit'
);

-- Should persist terminal failure state and keep the scheduled attempt
select results_eq(
    format(
        $$
            select claim_id, claimed_at, completed_at, error, failure_count, next_attempt_at, status
            from badge_award_job
            where badge_award_job_id = %L::uuid
        $$,
        :'terminalJobID'
    ),
    $$ values (null::uuid, null::timestamptz, current_timestamp, 'terminal failure', 2, '2026-01-01 00:00:00+00'::timestamptz, 'failed') $$,
    'Should persist terminal failure state and keep the scheduled attempt'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
