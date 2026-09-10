-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a170000-0000-0000-0000-000000000001'
\set eventCategoryID '4a170000-0000-0000-0000-000000000002'
\set eventID '4a170000-0000-0000-0000-000000000003'
\set groupCategoryID '4a170000-0000-0000-0000-000000000004'
\set groupID '4a170000-0000-0000-0000-000000000005'
\set proposal1ID '4a170000-0000-0000-0000-000000000006'
\set proposal2ID '4a170000-0000-0000-0000-000000000007'
\set submission1ID '4a170000-0000-0000-0000-000000000008'
\set submission2ID '4a170000-0000-0000-0000-000000000009'
\set user1ID '4a170000-0000-0000-0000-000000000010'
\set user2ID '4a170000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user2ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'alice-withdraw-cfs-submission'));

-- Session proposals
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values
    (
        :'proposal1ID',
        '2024-01-02 00:00:00+00',
        'Talk about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust Intro',
        :'user1ID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'user1ID'
    );

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cfs_description', 'CFS open',
    'cfs_enabled', true,
    'cfs_ends_at', current_timestamp + interval '1 day',
    'cfs_starts_at', current_timestamp - interval '1 day',
    'ends_at', current_timestamp + interval '8 days',
    'published', true,
    'starts_at', current_timestamp + interval '7 days'
));

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values
    (:'submission1ID', :'eventID', :'proposal1ID', 'not-reviewed'),
    (:'submission2ID', :'eventID', :'proposal2ID', 'approved');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject withdrawing another user's submission
select throws_ok(
    format(
        'select withdraw_cfs_submission(%L::uuid, %L::uuid)',
        :'user2ID',
        :'submission1ID'
    ),
    'OCG01',
    'submission not found or cannot be withdrawn',
    'Should reject withdrawing another user''s submission'
);

-- Withdraw submission
select lives_ok(
    format(
        $$
            select withdraw_cfs_submission(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'submission1ID'
    ),
    'Should execute withdraw_cfs_submission successfully'
);

-- Should withdraw submission
select is(
    (select status_id from cfs_submission where cfs_submission_id = :'submission1ID'::uuid),
    'withdrawn',
    'Should set submission status to withdrawn'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
            values (
                'submission_withdrawn',
                %L::uuid,
                'alice-withdraw-cfs-submission',
                'cfs_submission',
                %L::uuid
            )
        $$,
        :'user1ID',
        :'submission1ID'
    ),
    'Should create the expected audit row'
);

-- Should reject withdrawing approved submission
select throws_ok(
    format(
        'select withdraw_cfs_submission(%L::uuid, %L::uuid)',
        :'user1ID',
        :'submission2ID'
    ),
    'OCG01',
    'submission not found or cannot be withdrawn',
    'Should reject withdrawing approved submission'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
