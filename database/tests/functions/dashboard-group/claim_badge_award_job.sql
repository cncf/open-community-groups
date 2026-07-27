-- Tests claiming badge award jobs for durable worker ownership.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimProcessingID 'b3010000-0000-0000-0000-000000000001'
\set communityID 'b3010000-0000-0000-0000-000000000003'
\set futureJobID 'b3010000-0000-0000-0000-000000000004'
\set groupCategoryID 'b3010000-0000-0000-0000-000000000005'
\set groupID 'b3010000-0000-0000-0000-000000000006'
\set pendingFirstID 'b3010000-0000-0000-0000-000000000007'
\set pendingSecondID 'b3010000-0000-0000-0000-000000000008'
\set pendingThirdID 'b3010000-0000-0000-0000-000000000009'
\set processingJobID 'b3010000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the queued jobs
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Claim Community', '/logo', 'claim-community');

-- Category used by the queue group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the queued jobs
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Claim Group', 'claim-group');

-- Pending, future, and already processing jobs used by claim ordering
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    awarded_count,
    badge_snapshot,
    community_id,
    created_at,
    group_id,
    next_attempt_at,
    next_recipient_offset,
    recipient_count,
    skipped_count,
    status,

    claim_id,
    claimed_at
) values
    (:'processingJobID', 1, 'claim-admin', 0, '{"name":"Processing"}', :'communityID', '2026-01-01 00:00:00+00', :'groupID', '2026-01-01 00:00:00+00', 0, 1, 0, 'processing', :'claimProcessingID', '2026-01-01 00:00:00+00'),
    (:'pendingFirstID', 1, 'claim-admin', 0, '{"name":"First"}', :'communityID', '2026-01-02 00:00:00+00', :'groupID', '2026-01-02 00:00:00+00', 0, 1, 0, 'pending', null, null),
    (:'pendingSecondID', 1, 'claim-admin', 0, '{"name":"Second"}', :'communityID', '2026-01-03 00:00:00+00', :'groupID', '2026-01-03 00:00:00+00', 0, 1, 0, 'pending', null, null),
    (:'pendingThirdID', 1, 'claim-admin', 0, '{"name":"Third"}', :'communityID', '2026-01-04 00:00:00+00', :'groupID', '2026-01-04 00:00:00+00', 0, 1, 0, 'pending', null, null),
    (:'futureJobID', 1, 'claim-admin', 0, '{"name":"Future"}', :'communityID', '2026-01-05 00:00:00+00', :'groupID', '2099-01-01 00:00:00+00', 0, 1, 0, 'pending', null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should skip jobs already owned by another claim
select is(
    (claim_badge_award_job()->>'badge_award_job_id')::uuid,
    :'pendingFirstID'::uuid,
    'Should skip jobs already owned by another claim'
);

-- Should persist claim ownership on the selected job
select ok(
    (
        select status = 'processing'
            and claim_id is not null
            and claimed_at is not null
        from badge_award_job
        where badge_award_job_id = :'pendingFirstID'
    ),
    'Should persist claim ownership on the selected job'
);

-- Should rotate claim ids for separate processing claims
select ok(
    (
        with first_claim as (
            select claim_badge_award_job() as job
        ),
        second_claim as (
            select claim_badge_award_job() as job
            from first_claim
        )
        select first_claim.job->>'claim_id' <> second_claim.job->>'claim_id'
        from first_claim, second_claim
    ),
    'Should rotate claim ids for separate processing claims'
);

-- Should return null when no pending job is ready
select is(
    claim_badge_award_job(),
    null::jsonb,
    'Should return null when no pending job is ready'
);

-- Should leave future pending jobs unclaimed
select ok(
    (
        select status = 'pending'
            and claim_id is null
            and claimed_at is null
        from badge_award_job
        where badge_award_job_id = :'futureJobID'
    ),
    'Should leave future pending jobs unclaimed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
