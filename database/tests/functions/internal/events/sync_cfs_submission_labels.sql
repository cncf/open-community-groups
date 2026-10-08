-- Tests replacing the labels linked to a CFS submission.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set clearEmptyProposalID '0c1c0000-0000-0000-0000-000000000001'
\set clearEmptySubmissionID '0c1c0000-0000-0000-0000-000000000002'
\set clearNullProposalID '0c1c0000-0000-0000-0000-000000000003'
\set clearNullSubmissionID '0c1c0000-0000-0000-0000-000000000004'
\set communityID '0c1c0000-0000-0000-0000-000000000005'
\set eventCategoryID '0c1c0000-0000-0000-0000-000000000006'
\set eventID '0c1c0000-0000-0000-0000-000000000007'
\set eventOtherID '0c1c0000-0000-0000-0000-000000000008'
\set foreignLabelProposalID '0c1c0000-0000-0000-0000-000000000009'
\set foreignLabelSubmissionID '0c1c0000-0000-0000-0000-00000000000a'
\set groupCategoryID '0c1c0000-0000-0000-0000-00000000000b'
\set groupID '0c1c0000-0000-0000-0000-00000000000c'
\set label1ID '0c1c0000-0000-0000-0000-00000000000d'
\set label2ID '0c1c0000-0000-0000-0000-00000000000e'
\set labelOtherID '0c1c0000-0000-0000-0000-00000000000f'
\set otherProposalID '0c1c0000-0000-0000-0000-000000000010'
\set otherSubmissionID '0c1c0000-0000-0000-0000-000000000011'
\set replaceProposalID '0c1c0000-0000-0000-0000-000000000012'
\set replaceSubmissionID '0c1c0000-0000-0000-0000-000000000013'
\set userID '0c1c0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the CFS events
select fx_community(:'communityID');

-- Speaker who owns the session proposals
select fx_user(:'userID');

-- Event category used by the CFS events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the CFS events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Proposal cleared with an empty payload
insert into session_proposal (session_proposal_id, description, duration, session_proposal_level_id, title, user_id)
values (:'clearEmptyProposalID', 'Clear empty description', interval '30 minutes', 'beginner', 'Clear Empty', :'userID');

-- Proposal cleared with a null payload
insert into session_proposal (session_proposal_id, description, duration, session_proposal_level_id, title, user_id)
values (:'clearNullProposalID', 'Clear null description', interval '30 minutes', 'beginner', 'Clear Null', :'userID');

-- Proposal whose submission receives a foreign label
insert into session_proposal (session_proposal_id, description, duration, session_proposal_level_id, title, user_id)
values (:'foreignLabelProposalID', 'Foreign label description', interval '30 minutes', 'beginner', 'Foreign Label', :'userID');

-- Proposal submitted to the other event
insert into session_proposal (session_proposal_id, description, duration, session_proposal_level_id, title, user_id)
values (:'otherProposalID', 'Other description', interval '30 minutes', 'beginner', 'Other', :'userID');

-- Proposal whose submission labels are replaced
insert into session_proposal (session_proposal_id, description, duration, session_proposal_level_id, title, user_id)
values (:'replaceProposalID', 'Replace description', interval '30 minutes', 'beginner', 'Replace', :'userID');

-- Group hosting the CFS events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose submissions are labeled
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event owning the submission and label used by mismatch scenarios
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID');

-- Submission cleared with an empty payload
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'clearEmptySubmissionID', :'eventID', :'clearEmptyProposalID', 'not-reviewed');

-- Submission cleared with a null payload
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'clearNullSubmissionID', :'eventID', :'clearNullProposalID', 'not-reviewed');

-- Submission receiving a label from another event
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'foreignLabelSubmissionID', :'eventID', :'foreignLabelProposalID', 'not-reviewed');

-- Submission belonging to the other event
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'otherSubmissionID', :'eventOtherID', :'otherProposalID', 'not-reviewed');

-- Submission whose labels are replaced
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'replaceSubmissionID', :'eventID', :'replaceProposalID', 'not-reviewed');

-- First label of the event
insert into event_label (event_label_id, color, event_id, name)
values (:'label1ID', '#DBEAFE', :'eventID', 'Track / Backend');

-- Second label of the event
insert into event_label (event_label_id, color, event_id, name)
values (:'label2ID', '#FEE2E2', :'eventID', 'Track / Frontend');

-- Label of the other event
insert into event_label (event_label_id, color, event_id, name)
values (:'labelOtherID', '#CCFBF1', :'eventOtherID', 'Track / Other');

-- Label linked to the submission cleared with an empty payload
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'clearEmptySubmissionID', :'label1ID');

-- Label linked to the submission cleared with a null payload
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'clearNullSubmissionID', :'label1ID');

-- Label linked to the submission receiving a foreign label
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'foreignLabelSubmissionID', :'label1ID');

-- Label linked to the other event submission
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'otherSubmissionID', :'labelOtherID');

-- Label replaced on the submission
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values (:'replaceSubmissionID', :'label1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear labels when the payload is empty
select lives_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[]::uuid[])$$,
        :'clearEmptySubmissionID',
        :'eventID'
    ),
    'Should clear labels when the payload is empty'
);
select is(
    (select count(*)::int from cfs_submission_label where cfs_submission_id = :'clearEmptySubmissionID'),
    0,
    'Should remove existing labels for an empty payload'
);

-- Should clear labels when the payload is null
select lives_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, null)$$,
        :'clearNullSubmissionID',
        :'eventID'
    ),
    'Should clear labels when the payload is null'
);
select is(
    (select count(*)::int from cfs_submission_label where cfs_submission_id = :'clearNullSubmissionID'),
    0,
    'Should remove existing labels for a null payload'
);

-- Should reject labels from another event
select throws_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid])$$,
        :'foreignLabelSubmissionID',
        :'eventID',
        :'labelOtherID'
    ),
    'OCG01',
    'invalid event labels',
    'Should reject labels from another event'
);
select results_eq(
    format(
        $$select event_label_id from cfs_submission_label where cfs_submission_id = %L::uuid$$,
        :'foreignLabelSubmissionID'
    ),
    format($$values (%L::uuid)$$, :'label1ID'),
    'Should keep labels when rejecting labels from another event'
);

-- Should reject mismatched submission and event IDs
select throws_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid])$$,
        :'otherSubmissionID',
        :'eventID',
        :'label1ID'
    ),
    'OCG01',
    'submission not found',
    'Should reject mismatched submission and event IDs'
);
select results_eq(
    format(
        $$select event_label_id from cfs_submission_label where cfs_submission_id = %L::uuid$$,
        :'otherSubmissionID'
    ),
    format($$values (%L::uuid)$$, :'labelOtherID'),
    'Should leave mismatched submission labels unchanged'
);

-- Should replace labels and remove duplicates
select lives_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid, %L::uuid])$$,
        :'replaceSubmissionID',
        :'eventID',
        :'label2ID',
        :'label2ID'
    ),
    'Should replace labels and remove duplicates'
);
select results_eq(
    format(
        $$select event_label_id from cfs_submission_label where cfs_submission_id = %L::uuid$$,
        :'replaceSubmissionID'
    ),
    format($$values (%L::uuid)$$, :'label2ID'),
    'Should store the replacement labels once'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
