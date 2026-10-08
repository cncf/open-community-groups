-- Tests CFS submission label constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0090000-0000-0000-0000-000000000001'
\set duplicateLabelID 'c0090000-0000-0000-0000-000000000002'
\set duplicateProposalID 'c0090000-0000-0000-0000-000000000003'
\set duplicateSubmissionID 'c0090000-0000-0000-0000-000000000004'
\set eventCategoryID 'c0090000-0000-0000-0000-000000000005'
\set eventID 'c0090000-0000-0000-0000-000000000006'
\set groupCategoryID 'c0090000-0000-0000-0000-000000000007'
\set groupID 'c0090000-0000-0000-0000-000000000008'
\set labelCascadeLabelID 'c0090000-0000-0000-0000-000000000009'
\set labelCascadeProposalID 'c0090000-0000-0000-0000-000000000010'
\set labelCascadeSubmissionID 'c0090000-0000-0000-0000-000000000011'
\set missingLabelID 'c0090000-0000-0000-0000-000000000012'
\set missingSubmissionID 'c0090000-0000-0000-0000-000000000013'
\set submissionCascadeLabelID 'c0090000-0000-0000-0000-000000000014'
\set submissionCascadeProposalID 'c0090000-0000-0000-0000-000000000015'
\set submissionCascadeSubmissionID 'c0090000-0000-0000-0000-000000000016'
\set userID 'c0090000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the CFS event
select fx_community(:'communityID');

-- Speaker who owns the session proposals
select fx_user(:'userID');

-- Event category used by the CFS event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the CFS event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Proposal submitted by the duplicate rejection scenario
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'duplicateProposalID',
    'Duplicate proposal description',
    interval '30 minutes',
    'beginner',
    'Duplicate Proposal',
    :'userID'
);

-- Proposal submitted by the label cascade scenario
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'labelCascadeProposalID',
    'Label cascade proposal description',
    interval '30 minutes',
    'beginner',
    'Label Cascade Proposal',
    :'userID'
);

-- Proposal submitted by the submission cascade scenario
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'submissionCascadeProposalID',
    'Submission cascade proposal description',
    interval '30 minutes',
    'beginner',
    'Submission Cascade Proposal',
    :'userID'
);

-- Group hosting the CFS event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event receiving the CFS submissions
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Submission whose label link is duplicated
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'duplicateSubmissionID', :'eventID', :'duplicateProposalID', 'not-reviewed');

-- Submission whose label link is deleted through label cascade
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'labelCascadeSubmissionID', :'eventID', :'labelCascadeProposalID', 'not-reviewed');

-- Submission deleted through submission cascade
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (
    :'submissionCascadeSubmissionID',
    :'eventID',
    :'submissionCascadeProposalID',
    'not-reviewed'
);

-- Label linked twice by duplicate rejection
insert into event_label (event_label_id, color, event_id, name)
values (:'duplicateLabelID', '#DBEAFE', :'eventID', 'Duplicate');

-- Label deleted through label cascade
insert into event_label (event_label_id, color, event_id, name)
values (:'labelCascadeLabelID', '#DBEAFE', :'eventID', 'Label Cascade');

-- Label whose link is deleted through submission cascade
insert into event_label (event_label_id, color, event_id, name)
values (:'submissionCascadeLabelID', '#DBEAFE', :'eventID', 'Submission Cascade');

-- Link used by duplicate rejection
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'duplicateSubmissionID', :'duplicateLabelID');

-- Link deleted through label cascade
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'labelCascadeSubmissionID', :'labelCascadeLabelID');

-- Link deleted through submission cascade
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'submissionCascadeSubmissionID', :'submissionCascadeLabelID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete submission labels when labels are deleted
select lives_ok(
    format($$delete from event_label where event_label_id = %L::uuid$$, :'labelCascadeLabelID'),
    'Should delete labels linked to submissions'
);
select is(
    (
        select count(*)::int
        from cfs_submission_label
        where cfs_submission_id = :'labelCascadeSubmissionID'
    ),
    0,
    'Should delete submission labels when labels are deleted'
);
select is(
    (
        select count(*)::int
        from cfs_submission
        where cfs_submission_id = :'labelCascadeSubmissionID'
    ),
    1,
    'Should keep submissions when their labels are deleted'
);

-- Should delete submission labels when submissions are deleted
select lives_ok(
    format(
        $$delete from cfs_submission where cfs_submission_id = %L::uuid$$,
        :'submissionCascadeSubmissionID'
    ),
    'Should delete submissions with labels'
);
select is(
    (
        select count(*)::int
        from cfs_submission_label
        where event_label_id = :'submissionCascadeLabelID'
    ),
    0,
    'Should delete submission labels when submissions are deleted'
);
select is(
    (
        select count(*)::int
        from event_label
        where event_label_id = :'submissionCascadeLabelID'
    ),
    1,
    'Should keep labels when their submissions are deleted'
);

-- Should reject duplicate submission labels
select throws_ok(
    format(
        $$
            insert into cfs_submission_label (cfs_submission_id, event_label_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'duplicateSubmissionID',
        :'duplicateLabelID'
    ),
    '23505',
    null,
    'Should reject duplicate submission labels'
);

-- Should reject submission labels for missing labels
select throws_ok(
    format(
        $$
            insert into cfs_submission_label (cfs_submission_id, event_label_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'duplicateSubmissionID',
        :'missingLabelID'
    ),
    '23503',
    null,
    'Should reject submission labels for missing labels'
);

-- Should reject submission labels for missing submissions
select throws_ok(
    format(
        $$
            insert into cfs_submission_label (cfs_submission_id, event_label_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'missingSubmissionID',
        :'duplicateLabelID'
    ),
    '23503',
    null,
    'Should reject submission labels for missing submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
