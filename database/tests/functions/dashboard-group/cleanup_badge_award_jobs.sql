-- Tests cleanup of retained badge award job summaries.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b3020000-0000-0000-0000-000000000001'
\set groupCategoryID 'b3020000-0000-0000-0000-000000000002'
\set groupID 'b3020000-0000-0000-0000-000000000003'
\set oldCompletedJobID 'b3020000-0000-0000-0000-000000000004'
\set oldFailedJobID 'b3020000-0000-0000-0000-000000000005'
\set oldPendingJobID 'b3020000-0000-0000-0000-000000000006'
\set recentCompletedJobID 'b3020000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns cleanup fixtures
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Cleanup Community', '/logo', 'cleanup-community');

-- Category used by the cleanup group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns cleanup fixtures
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Cleanup Group', 'cleanup-group');

-- Terminal and active jobs spanning the retention boundary
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    awarded_count,
    badge_snapshot,
    community_id,
    completed_at,
    group_id,
    next_recipient_offset,
    recipient_count,
    skipped_count,
    status
) values
    (:'oldCompletedJobID', 1, 'cleanup-admin', 1, '{"name":"Old Completed"}', :'communityID', current_timestamp - interval '60 days', :'groupID', 1, 1, 0, 'completed'),
    (:'oldFailedJobID', 1, 'cleanup-admin', 0, '{"name":"Old Failed"}', :'communityID', current_timestamp - interval '60 days', :'groupID', 0, 1, 0, 'failed'),
    (:'oldPendingJobID', 1, 'cleanup-admin', 0, '{"name":"Old Pending"}', :'communityID', null, :'groupID', 0, 1, 0, 'pending'),
    (:'recentCompletedJobID', 1, 'cleanup-admin', 1, '{"name":"Recent Completed"}', :'communityID', current_timestamp - interval '1 day', :'groupID', 1, 1, 0, 'completed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a non-positive retention window
select throws_ok(
    $$select cleanup_badge_award_jobs(0)$$,
    'badge award job retention must be positive',
    'Should reject a non-positive retention window'
);

-- Should remove old terminal summaries after retention
select is(
    cleanup_badge_award_jobs(2592000),
    2,
    'Should remove old terminal summaries after retention'
);

-- Should delete only expired completed and failed jobs
select is(
    (
        select count(*)::integer
        from badge_award_job
        where badge_award_job_id in (:'oldCompletedJobID', :'oldFailedJobID')
    ),
    0,
    'Should delete only expired completed and failed jobs'
);

-- Should leave recent and pending summaries untouched
select is(
    (
        select count(*)::integer
        from badge_award_job
        where badge_award_job_id in (:'oldPendingJobID', :'recentCompletedJobID')
    ),
    2,
    'Should leave recent and pending summaries untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
