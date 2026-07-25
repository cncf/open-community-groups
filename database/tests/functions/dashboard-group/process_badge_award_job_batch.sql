-- Tests processing claimed badge award job batches.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b3030000-0000-0000-0000-000000000001'
\set badgeID 'b3030000-0000-0000-0000-000000000002'
\set batchOneID 'b3030000-0000-0000-0000-000000000003'
\set batchTwoID 'b3030000-0000-0000-0000-000000000004'
\set communityID 'b3030000-0000-0000-0000-000000000005'
\set completeClaimID 'b3030000-0000-0000-0000-000000000006'
\set completeJobID 'b3030000-0000-0000-0000-000000000007'
\set completeUserID 'b3030000-0000-0000-0000-000000000008'
\set duplicateClaimID 'b3030000-0000-0000-0000-000000000009'
\set duplicateJobID 'b3030000-0000-0000-0000-000000000010'
\set duplicateUserBadgeID 'b3030000-0000-0000-0000-000000000011'
\set duplicateUserID 'b3030000-0000-0000-0000-000000000012'
\set groupCategoryID 'b3030000-0000-0000-0000-000000000013'
\set groupID 'b3030000-0000-0000-0000-000000000014'
\set partialClaimID 'b3030000-0000-0000-0000-000000000015'
\set partialJobID 'b3030000-0000-0000-0000-000000000016'
\set rateClaimID 'b3030000-0000-0000-0000-000000000017'
\set rateJobID 'b3030000-0000-0000-0000-000000000018'
\set rateUserID 'b3030000-0000-0000-0000-000000000019'
\set recentAwardID 'b3030000-0000-0000-0000-000000000020'
\set recentAwardUserID 'b3030000-0000-0000-0000-000000000021'
\set statusListID 'b3030000-0000-0000-0000-000000000022'
\set wrongClaimID 'b3030000-0000-0000-0000-000000000023'
\set wrongJobID 'b3030000-0000-0000-0000-000000000024'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users that receive or own award-processing fixtures
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'actorID', 'hash', 'process-actor@example.test', true, 'process-actor'),
    (:'batchOneID', 'hash', 'process-one@example.test', true, 'process-one'),
    (:'batchTwoID', 'hash', 'process-two@example.test', true, 'process-two'),
    (:'completeUserID', 'hash', 'process-complete@example.test', true, 'process-complete'),
    (:'duplicateUserID', 'hash', 'process-duplicate@example.test', true, 'process-duplicate'),
    (:'rateUserID', 'hash', 'process-rate@example.test', true, 'process-rate'),
    (:'recentAwardUserID', 'hash', 'process-recent@example.test', true, 'process-recent');

-- Community that owns the processing fixtures
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Process Community', '/logo', 'process-community');

-- Category used by the processing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the processing fixtures
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Process Group', 'process-group');

-- Badge definition used to detect duplicate active credentials
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Criteria', 'Description', :'groupID', 'process.png', 'Process Badge');

-- Status list used for deterministic credential allocation
insert into badge_status_list (
    badge_status_list_id,
    allocation_offset,
    allocation_position,
    allocation_stride,
    group_id
) values (
    :'statusListID',
    0,
    0,
    1,
    :'groupID'
);

-- Existing active and recent credentials used by duplicate and rate-limit scenarios
insert into user_badge (
    user_badge_id, awarded_at, badge_status_list_id, display_order, group_id, snapshot, status_list_index,
    badge_id, user_id
) values
    (:'duplicateUserBadgeID', '2026-01-01 00:00:00+00', :'statusListID', 0, :'groupID', '{"name":"Process Badge"}', 10, :'badgeID', :'duplicateUserID'),
    (:'recentAwardID', current_timestamp, :'statusListID', 0, :'groupID', '{"name":"Recent Badge"}', 11, null, :'recentAwardUserID');

-- Processing jobs that exercise batching, completion, duplicate, rate, and claim validation paths
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    badge_snapshot,
    community_id,
    group_id,
    recipient_count,
    status,

    actor_user_id,
    badge_id,
    claim_id,
    claimed_at
) values
    (:'completeJobID', 1, 'process-actor', '{"name":"Process Badge"}', :'communityID', :'groupID', 1, 'processing', :'actorID', :'badgeID', :'completeClaimID', current_timestamp),
    (:'duplicateJobID', 1, 'process-actor', '{"name":"Process Badge"}', :'communityID', :'groupID', 1, 'processing', :'actorID', :'badgeID', :'duplicateClaimID', current_timestamp),
    (:'partialJobID', 2, 'process-actor', '{"name":"Process Badge"}', :'communityID', :'groupID', 2, 'processing', :'actorID', :'badgeID', :'partialClaimID', current_timestamp),
    (:'rateJobID', 1, 'process-actor', '{"name":"Process Badge"}', :'communityID', :'groupID', 1, 'processing', :'actorID', :'badgeID', :'rateClaimID', current_timestamp),
    (:'wrongJobID', 1, 'process-actor', '{"name":"Process Badge"}', :'communityID', :'groupID', 1, 'processing', :'actorID', :'badgeID', :'wrongClaimID', current_timestamp);

-- Recipients associated with each processing job
insert into badge_award_job_recipient (badge_award_job_id, position, user_id)
values
    (:'completeJobID', 0, :'completeUserID'),
    (:'duplicateJobID', 0, :'duplicateUserID'),
    (:'partialJobID', 0, :'batchOneID'),
    (:'partialJobID', 1, :'batchTwoID'),
    (:'rateJobID', 0, :'rateUserID'),
    (:'wrongJobID', 0, :'completeUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a mismatched processing claim
select throws_ok(
    format(
        $$select process_badge_award_job_batch(%L::uuid, gen_random_uuid(), 25, 1000000)$$,
        :'wrongJobID'
    ),
    'badge award job claim not found',
    'Should reject a mismatched processing claim'
);

-- Should release a rate-limited job without consuming recipients
select is(
    process_badge_award_job_batch(:'rateJobID', :'rateClaimID', 25, 1),
    jsonb_build_object(
        'completed', false,
        'processed_count', 0,
        'rate_limited', true
    ),
    'Should release a rate-limited job without consuming recipients'
);

-- Should persist rate-limited release state
select ok(
    (
        select status = 'pending'
            and claim_id is null
            and claimed_at is null
            and next_recipient_offset = 0
            and exists (
                select 1
                from badge_award_job_recipient bajr
                where bajr.badge_award_job_id = badge_award_job.badge_award_job_id
            )
        from badge_award_job
        where badge_award_job_id = :'rateJobID'
    ),
    'Should persist rate-limited release state'
);

-- Should process one bounded batch and leave unfinished work pending
select is(
    process_badge_award_job_batch(:'partialJobID', :'partialClaimID', 1, 1000000),
    jsonb_build_object(
        'completed', false,
        'processed_count', 1,
        'rate_limited', false
    ),
    'Should process one bounded batch and leave unfinished work pending'
);

-- Should persist partial batch progress
select ok(
    (
        select status = 'pending'
            and awarded_count = 1
            and claim_id is null
            and claimed_at is null
            and next_recipient_offset = 1
            and (
                select count(*)::integer
                from badge_award_job_recipient bajr
                where bajr.badge_award_job_id = badge_award_job.badge_award_job_id
            ) = 2
        from badge_award_job
        where badge_award_job_id = :'partialJobID'
    ),
    'Should persist partial batch progress'
);

-- Should skip duplicate active credentials during completion
select is(
    process_badge_award_job_batch(:'duplicateJobID', :'duplicateClaimID', 25, 1000000),
    jsonb_build_object(
        'completed', true,
        'processed_count', 1,
        'rate_limited', false
    ),
    'Should skip duplicate active credentials during completion'
);

-- Should persist duplicate skip without inserting another credential
select ok(
    (
        select status = 'completed'
            and awarded_count = 0
            and completed_at is not null
            and next_recipient_offset = 1
            and skipped_count = 1
            and (
                select count(*)::integer
                from user_badge ub
                where ub.badge_id = :'badgeID'
                and ub.revoked_at is null
                and ub.user_id = :'duplicateUserID'
            ) = 1
        from badge_award_job
        where badge_award_job_id = :'duplicateJobID'
    ),
    'Should persist duplicate skip without inserting another credential'
);

-- Should complete new credential issuance
select is(
    process_badge_award_job_batch(:'completeJobID', :'completeClaimID', 25, 1000000),
    jsonb_build_object(
        'completed', true,
        'processed_count', 1,
        'rate_limited', false
    ),
    'Should complete new credential issuance'
);

-- Should persist completion and remove recipient rows
select ok(
    (
        select status = 'completed'
            and awarded_count = 1
            and completed_at is not null
            and next_recipient_offset = 1
            and not exists (
                select 1
                from badge_award_job_recipient bajr
                where bajr.badge_award_job_id = badge_award_job.badge_award_job_id
            )
            and exists (
                select 1
                from user_badge ub
                where ub.badge_id = :'badgeID'
                and ub.revoked_at is null
                and ub.user_id = :'completeUserID'
            )
        from badge_award_job
        where badge_award_job_id = :'completeJobID'
    ),
    'Should persist completion and remove recipient rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
