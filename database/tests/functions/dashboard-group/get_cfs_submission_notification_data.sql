-- Tests loading the notification data of a CFS submission.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedProposalID '3a0e0000-0000-0000-0000-000000000010'
\set approvedSubmissionID '3a0e0000-0000-0000-0000-000000000011'
\set communityID '3a0e0000-0000-0000-0000-000000000001'
\set deletedEventID '3a0e0000-0000-0000-0000-000000000013'
\set deletedEventSubmissionID '3a0e0000-0000-0000-0000-000000000014'
\set eventCategoryID '3a0e0000-0000-0000-0000-000000000002'
\set eventID '3a0e0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a0e0000-0000-0000-0000-000000000004'
\set groupID '3a0e0000-0000-0000-0000-000000000005'
\set otherEventID '3a0e0000-0000-0000-0000-000000000009'
\set otherGroupID '3a0e0000-0000-0000-0000-000000000012'
\set proposalID '3a0e0000-0000-0000-0000-000000000006'
\set submissionID '3a0e0000-0000-0000-0000-000000000007'
\set userID '3a0e0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Speaker of the submissions
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Session proposal with information requested
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

-- Session proposal approved without an action required message
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'approvedProposalID',
    '2024-01-03 00:00:00+00',
    'Talk about Go',
    make_interval(mins => 30),
    'beginner',
    'Go Intro',
    :'userID'
);

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that owns none of the events
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event receiving the submissions
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Another event of the same group without submissions
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Deleted event of the owning group
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- CFS submission with an action required message
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

-- CFS submission without an action required message
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message
) values (
    :'approvedSubmissionID',
    :'eventID',
    :'approvedProposalID',
    'approved',
    null
);

-- CFS submission of the deleted event
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values (
    :'deletedEventSubmissionID',
    :'deletedEventID',
    :'proposalID',
    'approved'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should omit the action required message when it is null
select is(
    get_cfs_submission_notification_data(:'groupID'::uuid, :'eventID'::uuid, :'approvedSubmissionID'::uuid)::jsonb,
    jsonb_build_object(
        'status_id', 'approved',
        'status_name', 'Approved',
        'user_id', :'userID'::uuid
    ),
    'Should omit the action required message when it is null'
);

-- Should return null when the event belongs to another group
select is(
    get_cfs_submission_notification_data(:'otherGroupID'::uuid, :'eventID'::uuid, :'submissionID'::uuid)::jsonb,
    null::jsonb,
    'Should return null when the event belongs to another group'
);

-- Should return null when the event is deleted
select is(
    get_cfs_submission_notification_data(:'groupID'::uuid, :'deletedEventID'::uuid, :'deletedEventSubmissionID'::uuid)::jsonb,
    null::jsonb,
    'Should return null when the event is deleted'
);

-- Should return null when the submission belongs to another event
select is(
    get_cfs_submission_notification_data(:'groupID'::uuid, :'otherEventID'::uuid, :'submissionID'::uuid)::jsonb,
    null::jsonb,
    'Should return null when the submission belongs to another event'
);

-- Should return submission notification data
select is(
    get_cfs_submission_notification_data(:'groupID'::uuid, :'eventID'::uuid, :'submissionID'::uuid)::jsonb,
    jsonb_build_object(
        'status_id', 'information-requested',
        'status_name', 'Information requested',
        'user_id', :'userID'::uuid,

        'action_required_message', 'Need more info'
    ),
    'Should return submission notification data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
