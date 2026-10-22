-- Tests badge award job constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'c0e30000-0000-0000-0000-000000000001'
\set communityID 'c0e30000-0000-0000-0000-000000000002'
\set groupCategoryID 'c0e30000-0000-0000-0000-000000000003'
\set groupID 'c0e30000-0000-0000-0000-000000000004'
\set strayClaimID 'c0e30000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group awarding the badges
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept claimed processing jobs
select lives_ok(
    format(
        $$
            insert into badge_award_job (
                accepted_count,
                actor_username,
                badge_snapshot,
                community_id,
                group_id,
                recipient_count,
                status,

                claim_id,
                claimed_at
            ) values (
                2,
                'organizer',
                '{"name": "Speaker"}'::jsonb,
                %L::uuid,
                %L::uuid,
                2,
                'processing',

                %L::uuid,
                current_timestamp
            )
        $$,
        :'communityID',
        :'groupID',
        :'claimID'
    ),
    'Should accept claimed processing jobs'
);

-- Should accept completed jobs that processed every recipient
select lives_ok(
    format(
        $$
            insert into badge_award_job (
                accepted_count,
                actor_username,
                awarded_count,
                badge_snapshot,
                community_id,
                group_id,
                next_recipient_offset,
                recipient_count,
                skipped_count,
                status,

                completed_at
            ) values (
                2,
                'organizer',
                2,
                '{"name": "Speaker"}'::jsonb,
                %L::uuid,
                %L::uuid,
                2,
                3,
                1,
                'completed',

                current_timestamp
            )
        $$,
        :'communityID',
        :'groupID'
    ),
    'Should accept completed jobs that processed every recipient'
);

-- Should accept failed jobs with a completion time
select lives_ok(
    format(
        $$
            insert into badge_award_job (
                accepted_count,
                actor_username,
                awarded_count,
                badge_snapshot,
                community_id,
                group_id,
                next_recipient_offset,
                recipient_count,
                status,

                completed_at,
                error
            ) values (
                2,
                'organizer',
                1,
                '{"name": "Speaker"}'::jsonb,
                %L::uuid,
                %L::uuid,
                1,
                2,
                'failed',

                current_timestamp,
                'badge was deleted'
            )
        $$,
        :'communityID',
        :'groupID'
    ),
    'Should accept failed jobs with a completion time'
);

-- Should reject completed jobs with unprocessed recipients
select throws_ok(
    format(
        $$
            insert into badge_award_job (
                accepted_count,
                actor_username,
                awarded_count,
                badge_snapshot,
                community_id,
                group_id,
                next_recipient_offset,
                recipient_count,
                status,

                completed_at
            ) values (
                2,
                'organizer',
                1,
                '{"name": "Speaker"}'::jsonb,
                %L::uuid,
                %L::uuid,
                2,
                2,
                'completed',

                current_timestamp
            )
        $$,
        :'communityID',
        :'groupID'
    ),
    '23514',
    'new row for relation "badge_award_job" violates check constraint "badge_award_job_counts_chk"',
    'Should reject completed jobs with unprocessed recipients'
);

-- Should reject pending jobs holding a claim
select throws_ok(
    format(
        $$
            insert into badge_award_job (
                accepted_count,
                actor_username,
                badge_snapshot,
                community_id,
                group_id,
                recipient_count,
                status,

                claim_id,
                claimed_at
            ) values (
                2,
                'organizer',
                '{"name": "Speaker"}'::jsonb,
                %L::uuid,
                %L::uuid,
                2,
                'pending',

                %L::uuid,
                current_timestamp
            )
        $$,
        :'communityID',
        :'groupID',
        :'strayClaimID'
    ),
    '23514',
    'new row for relation "badge_award_job" violates check constraint "badge_award_job_claim_chk"',
    'Should reject pending jobs holding a claim'
);

-- Should reject pending jobs with a completion time
select throws_ok(
    format(
        $$
            insert into badge_award_job (
                accepted_count,
                actor_username,
                badge_snapshot,
                community_id,
                group_id,
                recipient_count,
                status,

                completed_at
            ) values (
                2,
                'organizer',
                '{"name": "Speaker"}'::jsonb,
                %L::uuid,
                %L::uuid,
                2,
                'pending',

                current_timestamp
            )
        $$,
        :'communityID',
        :'groupID'
    ),
    '23514',
    'new row for relation "badge_award_job" violates check constraint "badge_award_job_terminal_chk"',
    'Should reject pending jobs with a completion time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
