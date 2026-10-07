-- Tests consolidating CFS labels into event labels shared by sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set labelBackendID '89000000-0000-0000-0000-000000000005'
\set labelFrontendID '89000000-0000-0000-0000-000000000006'
\set labelOtherEventID '89000000-0000-0000-0000-000000000007'
\set labeledEventID '89000000-0000-0000-0000-000000000008'
\set labeledLinkedSessionID '89000000-0000-0000-0000-000000000010'
\set labeledLinkedSubmissionID '89000000-0000-0000-0000-000000000011'
\set labeledUnlinkedSubmissionID '89000000-0000-0000-0000-000000000014'
\set otherEventID '89000000-0000-0000-0000-000000000015'
\set otherSubmissionID '89000000-0000-0000-0000-000000000017'
\set unlabeledLinkedSessionID '89000000-0000-0000-0000-000000000020'
\set unlinkedSessionID '89000000-0000-0000-0000-000000000022'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should drop the replaced CFS label table
select hasnt_table('event_cfs_label');

-- Should keep label identifiers, owners, names, colors and creation times
select results_eq(
    $$
        select event_label_id, event_id, name, color, created_at
        from event_label
        order by created_at
    $$,
    format(
        $$
            values
                (%L::uuid, %L::uuid, 'track / backend'::text, '#DBEAFE'::text, '2024-01-01 10:00:00+00'::timestamptz),
                (%L::uuid, %L::uuid, 'track / frontend'::text, '#FEE2E2'::text, '2024-01-02 10:00:00+00'::timestamptz),
                (%L::uuid, %L::uuid, 'track / backend'::text, '#CCFBF1'::text, '2024-01-03 10:00:00+00'::timestamptz)
        $$,
        :'labelBackendID', :'labeledEventID',
        :'labelFrontendID', :'labeledEventID',
        :'labelOtherEventID', :'otherEventID'
    ),
    'Should keep label identifiers, owners, names, colors and creation times'
);

-- Should keep submission label links
select results_eq(
    $$
        select cfs_submission_id, event_label_id, created_at
        from cfs_submission_label
        order by created_at
    $$,
    format(
        $$
            values
                (%L::uuid, %L::uuid, '2024-02-01 10:00:00+00'::timestamptz),
                (%L::uuid, %L::uuid, '2024-02-02 10:00:00+00'::timestamptz),
                (%L::uuid, %L::uuid, '2024-02-03 10:00:00+00'::timestamptz),
                (%L::uuid, %L::uuid, '2024-02-04 10:00:00+00'::timestamptz)
        $$,
        :'labeledLinkedSubmissionID', :'labelBackendID',
        :'labeledLinkedSubmissionID', :'labelFrontendID',
        :'labeledUnlinkedSubmissionID', :'labelFrontendID',
        :'otherSubmissionID', :'labelOtherEventID'
    ),
    'Should keep submission label links'
);

-- Should copy labels only to sessions linked to labeled submissions
select results_eq(
    $$
        select session_id, event_label_id
        from session_label
        order by session_id, event_label_id
    $$,
    format(
        $$
            values
                (%L::uuid, %L::uuid),
                (%L::uuid, %L::uuid)
        $$,
        :'labeledLinkedSessionID', :'labelBackendID',
        :'labeledLinkedSessionID', :'labelFrontendID'
    ),
    'Should copy labels only to sessions linked to labeled submissions'
);

-- Should leave sessions without labeled submissions unlabeled
select is(
    (
        select count(*)::int
        from session_label
        where session_id in (:'unlabeledLinkedSessionID', :'unlinkedSessionID')
    ),
    0,
    'Should leave sessions without labeled submissions unlabeled'
);

-- Should drop the replaced label functions
select hasnt_function('list_event_cfs_labels');
select hasnt_function('sync_event_cfs_labels');
select hasnt_function('validate_cfs_submission_label_ids');
select hasnt_function('validate_event_cfs_labels_payload');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
