-- Tests claiming badge award jobs for durable worker ownership.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimProcessingID 'b3010000-0000-0000-0000-000000000001'
\set communityID 'b3010000-0000-0000-0000-000000000003'
\set futureJobID 'b3010000-0000-0000-0000-000000000004'
\set groupCategoryID 'b3010000-0000-0000-0000-000000000005'
\set groupID 'b3010000-0000-0000-0000-000000000006'
\set pendingFirstID 'b3010000-0000-0000-0000-000000000007'
\set pendingSecondID 'b3010000-0000-0000-0000-000000000009'
\set pendingThirdID 'b3010000-0000-0000-0000-000000000008'
\set processingJobID 'b3010000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Pending, future, and already processing jobs used by claim ordering. The
-- second and third pending jobs are seeded so only next_attempt_at puts the
-- second first: created_at, id and insertion order all favor the third
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
    (:'pendingThirdID', 1, 'claim-admin', 0, '{"name":"Third"}', :'communityID', '2026-01-03 00:00:00+00', :'groupID', '2026-01-04 00:00:00+00', 0, 1, 0, 'pending', null, null),
    (:'pendingSecondID', 1, 'claim-admin', 0, '{"name":"Second"}', :'communityID', '2026-01-04 00:00:00+00', :'groupID', '2026-01-03 00:00:00+00', 0, 1, 0, 'pending', null, null),
    (:'futureJobID', 1, 'claim-admin', 0, '{"name":"Future"}', :'communityID', '2026-01-05 00:00:00+00', :'groupID', '2099-01-01 00:00:00+00', 0, 1, 0, 'pending', null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Queue walk: claims are global, so each claim below takes the next due job
-- and the null claim relies on the earlier claims having drained the queue

-- Claim the first due job and keep its payload for the ownership checks
select claim_badge_award_job() as "firstClaim" \gset

-- Should skip jobs already owned by another claim
select is(
    (:'firstClaim'::jsonb->>'badge_award_job_id')::uuid,
    :'pendingFirstID'::uuid,
    'Should skip jobs already owned by another claim'
);

-- Should persist the returned claim ownership on the selected job
select results_eq(
    format(
        $$
            select status, claim_id, claimed_at
            from badge_award_job
            where badge_award_job_id = %L::uuid
        $$,
        :'pendingFirstID'
    ),
    format(
        $$ values ('processing', %L::uuid, current_timestamp) $$,
        :'firstClaim'::jsonb->>'claim_id'
    ),
    'Should persist the returned claim ownership on the selected job'
);

-- Should claim the remaining due jobs in due order
select results_eq(
    $$
        select (claim_badge_award_job()->>'badge_award_job_id')::uuid
        from generate_series(1, 2)
    $$,
    format($$ values (%L::uuid), (%L::uuid) $$, :'pendingSecondID', :'pendingThirdID'),
    'Should claim the remaining due jobs in due order'
);

-- Should rotate claim ids for separate processing claims
select is(
    (
        select count(distinct claim_id)::integer
        from badge_award_job
        where badge_award_job_id in (:'pendingFirstID', :'pendingSecondID', :'pendingThirdID')
    ),
    3,
    'Should rotate claim ids for separate processing claims'
);

-- Should return null when no pending job is ready
select is(
    claim_badge_award_job(),
    null::jsonb,
    'Should return null when no pending job is ready'
);

-- Should leave future and foreign-claimed jobs untouched
select results_eq(
    format(
        $$
            select badge_award_job_id, status, claim_id, claimed_at
            from badge_award_job
            where badge_award_job_id in (%L::uuid, %L::uuid)
            order by badge_award_job_id
        $$,
        :'futureJobID', :'processingJobID'
    ),
    format(
        $$ values
            (%L::uuid, 'pending', null::uuid, null::timestamptz),
            (%L::uuid, 'processing', %L::uuid, '2026-01-01 00:00:00+00'::timestamptz)
        $$,
        :'futureJobID', :'processingJobID', :'claimProcessingID'
    ),
    'Should leave future and foreign-claimed jobs untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
