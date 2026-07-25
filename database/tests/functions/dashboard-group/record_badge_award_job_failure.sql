-- Tests recording badge award job processing failures.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b3040000-0000-0000-0000-000000000001'
\set groupCategoryID 'b3040000-0000-0000-0000-000000000002'
\set groupID 'b3040000-0000-0000-0000-000000000003'
\set retryClaimID 'b3040000-0000-0000-0000-000000000004'
\set retryJobID 'b3040000-0000-0000-0000-000000000005'
\set terminalClaimID 'b3040000-0000-0000-0000-000000000006'
\set terminalJobID 'b3040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns failure fixtures
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Failure Community', '/logo', 'failure-community');

-- Category used by the failure group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns failure fixtures
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Failure Group', 'failure-group');

-- Processing jobs used by retry and terminal failure scenarios
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    badge_snapshot,
    community_id,
    failure_count,
    group_id,
    recipient_count,
    status,

    claim_id,
    claimed_at
) values
    (:'retryJobID', 1, 'failure-admin', '{"name":"Retry"}', :'communityID', 0, :'groupID', 1, 'processing', :'retryClaimID', current_timestamp),
    (:'terminalJobID', 1, 'failure-admin', '{"name":"Terminal"}', :'communityID', 1, :'groupID', 1, 'processing', :'terminalClaimID', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a non-positive failure limit
select throws_ok(
    format(
        $$select record_badge_award_job_failure(%L::uuid, %L::uuid, 'bad limit', 0)$$,
        :'retryJobID', :'retryClaimID'
    ),
    'badge award job failure limit must be positive',
    'Should reject a non-positive failure limit'
);

-- Should reject a missing processing claim
select throws_ok(
    format(
        $$select record_badge_award_job_failure(%L::uuid, gen_random_uuid(), 'missing claim', 10)$$,
        :'retryJobID'
    ),
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
select ok(
    (
        select status = 'pending'
            and claim_id is null
            and claimed_at is null
            and completed_at is null
            and error = 'retry failure'
            and failure_count = 1
            and next_attempt_at > current_timestamp
        from badge_award_job
        where badge_award_job_id = :'retryJobID'
    ),
    'Should persist retry failure state with backoff'
);

-- Should terminally fail after the failure limit
select is(
    record_badge_award_job_failure(:'terminalJobID', :'terminalClaimID', 'terminal failure', 2),
    true,
    'Should terminally fail after the failure limit'
);

-- Should persist terminal failure state and error text
select ok(
    (
        select status = 'failed'
            and claim_id is null
            and claimed_at is null
            and completed_at is not null
            and error = 'terminal failure'
            and failure_count = 2
        from badge_award_job
        where badge_award_job_id = :'terminalJobID'
    ),
    'Should persist terminal failure state and error text'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
