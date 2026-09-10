-- Tests deleting user-owned session proposals.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a060000-0000-0000-0000-000000000001'
\set eventCategoryID '4a060000-0000-0000-0000-000000000002'
\set eventID '4a060000-0000-0000-0000-000000000003'
\set groupCategoryID '4a060000-0000-0000-0000-000000000004'
\set groupID '4a060000-0000-0000-0000-000000000005'
\set otherUserProposalID '4a060000-0000-0000-0000-000000000006'
\set proposalWithSubmissionID '4a060000-0000-0000-0000-000000000007'
\set sessionProposalID '4a060000-0000-0000-0000-000000000008'
\set user2ID '4a060000-0000-0000-0000-000000000009'
\set userID '4a060000-0000-0000-0000-000000000010'

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
select fx_user(:'userID', jsonb_build_object('username', 'alice-delete-session-proposal'));

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

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'sessionProposalID',
    '2024-01-02 00:00:00+00',
    'Session about Rust',
    make_interval(mins => 45),
    'beginner',
    'Rust 101',
    :'userID'
);

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalWithSubmissionID',
    '2024-01-03 00:00:00+00',
    'Session about Go',
    make_interval(mins => 45),
    'beginner',
    'Go 101',
    :'userID'
);

-- CFS submission
insert into cfs_submission (event_id, session_proposal_id, status_id)
values (:'eventID', :'proposalWithSubmissionID'::uuid, 'not-reviewed');

-- Session proposal (other user)
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'otherUserProposalID',
    '2024-01-04 00:00:00+00',
    'Session about Python',
    make_interval(mins => 45),
    'beginner',
    'Python 101',
    :'user2ID'
);

-- CFS submission (other user)
insert into cfs_submission (event_id, session_proposal_id, status_id)
values (:'eventID', :'otherUserProposalID'::uuid, 'not-reviewed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Delete session proposal
select lives_ok(
    format(
        'select delete_session_proposal(%L::uuid, %L::uuid)',
        :'userID',
        :'sessionProposalID'
    ),
    'Should execute delete_session_proposal successfully'
);

-- Should delete session proposal
select is(
    (select count(*) from session_proposal where session_proposal_id = :'sessionProposalID'::uuid),
    0::bigint,
    'Should remove session proposal record'
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
            'session_proposal_deleted',
            %L::uuid,
            'alice-delete-session-proposal',
            'session_proposal',
            %L::uuid
        )
        $$,
        :'userID',
        :'sessionProposalID'
    ),
    'Should create the expected audit row'
);

-- Should reject deleting proposals with submissions
select throws_ok(
    format(
        'select delete_session_proposal(%L::uuid, %L::uuid)',
        :'userID',
        :'proposalWithSubmissionID'
    ),
    'OCG01',
    'session proposal has submissions',
    'Should reject deleting proposals with submissions'
);

-- Should not leak linked sessions for other users
select throws_ok(
    format(
        'select delete_session_proposal(%L::uuid, %L::uuid)',
        :'userID',
        :'otherUserProposalID'
    ),
    'OCG01',
    'session proposal not found',
    'Should not leak submissions for other users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
