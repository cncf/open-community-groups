-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e0a0000-0000-0000-0000-000000000001'
\set eventCategoryID '5e0a0000-0000-0000-0000-000000000002'
\set eventID '5e0a0000-0000-0000-0000-000000000003'
\set groupCategoryID '5e0a0000-0000-0000-0000-000000000004'
\set groupID '5e0a0000-0000-0000-0000-000000000005'
\set proposalPendingID '5e0a0000-0000-0000-0000-000000000006'
\set proposalRustID '5e0a0000-0000-0000-0000-000000000007'
\set proposalZigID '5e0a0000-0000-0000-0000-000000000008'
\set submissionID '5e0a0000-0000-0000-0000-000000000009'
\set user1ID '5e0a0000-0000-0000-0000-00000000000a'
\set user2ID '5e0a0000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
        :'proposalRustID',
        '2024-01-02 00:00:00+00',
        'Talk about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust Intro',
        :'user1ID'
    ),
    (
        :'proposalZigID',
        '2024-01-03 00:00:00+00',
        'Talk about Zig',
        make_interval(mins => 60),
        'intermediate',
        'Zig Intro',
        :'user1ID'
    );

-- Session proposals available to the CFS listing scenarios
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    user_id
) values (
    :'proposalPendingID',
    '2024-01-04 00:00:00+00',
    'Talk about Python',
    make_interval(mins => 30),
    'advanced',
    'pending-co-speaker-response',
    'Python Intro',
    :'user1ID'
);

-- Event with scenario-specific state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- CFS submission
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values (
    :'submissionID',
    :'eventID',
    :'proposalZigID',
    'not-reviewed'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list proposals with submission status for event
select is(
    list_user_session_proposals_for_cfs_event(:'user1ID'::uuid, :'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'created_at', 1704153600,
            'description', 'Talk about Rust',
            'duration_minutes', 45,
            'is_submitted', false,
            'session_proposal_id', :'proposalRustID'::uuid,
            'session_proposal_level_id', 'beginner',
            'session_proposal_level_name', 'Beginner',
            'session_proposal_status_id', 'ready-for-submission',
            'status_name', 'Ready for submission',
            'title', 'Rust Intro'
        ),
        jsonb_build_object(
            'created_at', 1704240000,
            'description', 'Talk about Zig',
            'duration_minutes', 60,
            'is_submitted', true,
            'session_proposal_id', :'proposalZigID'::uuid,
            'session_proposal_level_id', 'intermediate',
            'session_proposal_level_name', 'Intermediate',
            'session_proposal_status_id', 'ready-for-submission',
            'status_name', 'Ready for submission',
            'submission_status_id', 'not-reviewed',
            'submission_status_name', 'Not reviewed',
            'title', 'Zig Intro'
        )
    ),
    'Should list proposals with submission status for event'
);

-- Should return empty list for users without proposals
select is(
    list_user_session_proposals_for_cfs_event(:'user2ID'::uuid, :'eventID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list for users without proposals'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
