-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0e0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a0e0000-0000-0000-0000-000000000002'
\set eventID '3a0e0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a0e0000-0000-0000-0000-000000000004'
\set groupID '3a0e0000-0000-0000-0000-000000000005'
\set proposalID '3a0e0000-0000-0000-0000-000000000006'
\set submissionID '3a0e0000-0000-0000-0000-000000000007'
\set userID '3a0e0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


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
    :'proposalID',
    '2024-01-02 00:00:00+00',
    'Talk about Rust',
    make_interval(mins => 45),
    'beginner',
    'Rust Intro',
    :'userID'
);

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- CFS submission
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message
) values (
    :'submissionID',
    :'eventID',
    :'proposalID',
    'information-requested',
    'Need more info'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return submission notification data
select is(
    get_cfs_submission_notification_data(:'eventID'::uuid, :'submissionID'::uuid)::jsonb,
    jsonb_build_object(
        'action_required_message', 'Need more info',
        'status_id', 'information-requested',
        'status_name', 'Information requested',
        'user_id', :'userID'::uuid
    ),
    'Should return submission notification data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
