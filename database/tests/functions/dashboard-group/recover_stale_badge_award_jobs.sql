-- Tests recovery of stale badge award job claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b3050000-0000-0000-0000-000000000001'
\set freshClaimID 'b3050000-0000-0000-0000-000000000002'
\set freshJobID 'b3050000-0000-0000-0000-000000000003'
\set groupCategoryID 'b3050000-0000-0000-0000-000000000004'
\set groupID 'b3050000-0000-0000-0000-000000000005'
\set pendingJobID 'b3050000-0000-0000-0000-000000000006'
\set staleClaimID 'b3050000-0000-0000-0000-000000000007'
\set staleJobID 'b3050000-0000-0000-0000-000000000008'
\set terminalClaimID 'b3050000-0000-0000-0000-000000000009'
\set terminalJobID 'b3050000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns recovery fixtures
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Recovery Community', '/logo', 'recovery-community');

-- Category used by the recovery group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns recovery fixtures
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Recovery Group', 'recovery-group');

-- Fresh, pending, stale retry, and stale terminal jobs used by recovery scenarios
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
    (:'freshJobID', 1, 'recovery-admin', '{"name":"Fresh"}', :'communityID', 0, :'groupID', 1, 'processing', :'freshClaimID', current_timestamp),
    (:'pendingJobID', 1, 'recovery-admin', '{"name":"Pending"}', :'communityID', 0, :'groupID', 1, 'pending', null, null),
    (:'staleJobID', 1, 'recovery-admin', '{"name":"Stale"}', :'communityID', 0, :'groupID', 1, 'processing', :'staleClaimID', current_timestamp - interval '1 hour'),
    (:'terminalJobID', 1, 'recovery-admin', '{"name":"Terminal"}', :'communityID', 9, :'groupID', 1, 'processing', :'terminalClaimID', current_timestamp - interval '1 hour');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a non-positive failure limit
select throws_ok(
    $$select recover_stale_badge_award_jobs(60, 0)$$,
    'badge award job failure limit must be positive',
    'Should reject a non-positive failure limit'
);

-- Should reject a non-positive processing timeout
select throws_ok(
    $$select recover_stale_badge_award_jobs(0, 10)$$,
    'badge award job processing timeout must be positive',
    'Should reject a non-positive processing timeout'
);

-- Should recover only stale processing claims
select is(
    recover_stale_badge_award_jobs(60, 10),
    2,
    'Should recover only stale processing claims'
);

-- Should release stale work with failure metadata
select ok(
    (
        select status = 'pending'
            and claim_id is null
            and claimed_at is null
            and completed_at is null
            and error = 'badge award worker claim expired'
            and failure_count = 1
        from badge_award_job
        where badge_award_job_id = :'staleJobID'
    ),
    'Should release stale work with failure metadata'
);

-- Should terminally fail exhausted stale work and leave fresh claims untouched
select ok(
    (
        select terminal.status = 'failed'
            and terminal.completed_at is not null
            and terminal.failure_count = 10
            and fresh.status = 'processing'
            and fresh.claim_id = :'freshClaimID'::uuid
            and pending.status = 'pending'
        from badge_award_job terminal
        cross join badge_award_job fresh
        cross join badge_award_job pending
        where terminal.badge_award_job_id = :'terminalJobID'
        and fresh.badge_award_job_id = :'freshJobID'
        and pending.badge_award_job_id = :'pendingJobID'
    ),
    'Should terminally fail exhausted stale work and leave fresh claims untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
