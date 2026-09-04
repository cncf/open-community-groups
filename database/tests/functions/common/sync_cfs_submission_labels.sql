-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c1c0000-0000-0000-0000-000000000001'
\set eventCategoryID '0c1c0000-0000-0000-0000-000000000002'
\set eventID '0c1c0000-0000-0000-0000-000000000003'
\set eventOtherID '0c1c0000-0000-0000-0000-000000000004'
\set groupCategoryID '0c1c0000-0000-0000-0000-000000000005'
\set groupID '0c1c0000-0000-0000-0000-000000000006'
\set label1ID '0c1c0000-0000-0000-0000-000000000007'
\set label2ID '0c1c0000-0000-0000-0000-000000000008'
\set labelOtherID '0c1c0000-0000-0000-0000-000000000009'
\set proposalID '0c1c0000-0000-0000-0000-00000000000a'
\set proposalOtherID '0c1c0000-0000-0000-0000-00000000000b'
\set submissionID '0c1c0000-0000-0000-0000-00000000000c'
\set submissionOtherID '0c1c0000-0000-0000-0000-00000000000d'
\set userID '0c1c0000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users, groups and events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID');

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'Track / Backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'Track / Frontend', '#FEE2E2'),
    (:'labelOtherID', :'eventOtherID', 'Track / Other', '#CCFBF1');

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    user_id,
    title,
    description,
    duration,
    session_proposal_level_id
) values
    (
        :'proposalID',
        :'userID',
        'Proposal',
        'Proposal description',
        interval '45 minutes',
        'intermediate'
    ),
    (
        :'proposalOtherID',
        :'userID',
        'Other Proposal',
        'Other proposal description',
        interval '45 minutes',
        'intermediate'
    );

-- CFS submission
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values
    (:'submissionID', :'eventID', :'proposalID', 'not-reviewed'),
    (:'submissionOtherID', :'eventOtherID', :'proposalOtherID', 'not-reviewed');

-- Existing submission label
insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
values
    (:'submissionID', :'label1ID'),
    (:'submissionOtherID', :'labelOtherID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should replace labels and remove duplicates
select lives_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'submissionID',
        :'eventID',
        :'label2ID',
        :'label2ID',
        :'label1ID'
    ),
    'Should replace labels and remove duplicates'
);

select is(
    (
        select jsonb_agg(event_cfs_label_id order by event_cfs_label_id)
        from cfs_submission_label
        where cfs_submission_id = :'submissionID'::uuid
    ),
    jsonb_build_array(:'label1ID'::uuid, :'label2ID'::uuid),
    'Should store unique labels'
);

-- Should clear labels when payload is null
select lives_ok(
    format($$select sync_cfs_submission_labels(%L::uuid, %L::uuid, null)$$, :'submissionID', :'eventID'),
    'Should clear labels when payload is null'
);

select is(
    (select count(*) from cfs_submission_label where cfs_submission_id = :'submissionID'::uuid),
    0::bigint,
    'Should remove existing labels'
);

-- Should reject mismatched submission and event IDs
select throws_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid])$$,
        :'submissionOtherID',
        :'eventID',
        :'label1ID'
    ),
    'OCG01',
    'submission not found',
    'Should reject mismatched submission and event IDs'
);

select is(
    (
        select jsonb_agg(event_cfs_label_id order by event_cfs_label_id)
        from cfs_submission_label
        where cfs_submission_id = :'submissionOtherID'::uuid
    ),
    jsonb_build_array(:'labelOtherID'::uuid),
    'Should leave mismatched submission labels unchanged'
);

-- Should reject labels from another event
select throws_ok(
    format(
        $$select sync_cfs_submission_labels(%L::uuid, %L::uuid, array[%L::uuid])$$,
        :'submissionID',
        :'eventID',
        :'labelOtherID'
    ),
    'OCG01',
    'invalid event CFS labels',
    'Should reject labels from another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
