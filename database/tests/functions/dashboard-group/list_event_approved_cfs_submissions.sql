-- Tests listing approved CFS submissions available for event sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a170000-0000-0000-0000-000000000001'
\set deletedEventID '3a170000-0000-0000-0000-000000000021'
\set deletedEventSubmissionID '3a170000-0000-0000-0000-000000000022'
\set eventCategoryID '3a170000-0000-0000-0000-000000000002'
\set eventID '3a170000-0000-0000-0000-000000000003'
\set eventNoApprovedID '3a170000-0000-0000-0000-000000000004'
\set groupCategoryID '3a170000-0000-0000-0000-000000000005'
\set groupID '3a170000-0000-0000-0000-000000000006'
\set labelAlphaID '3a170000-0000-0000-0000-000000000019'
\set labelZetaID '3a170000-0000-0000-0000-000000000018'
\set otherGroupID '3a170000-0000-0000-0000-000000000020'
\set proposal1ID '3a170000-0000-0000-0000-000000000007'
\set proposal2ID '3a170000-0000-0000-0000-000000000008'
\set proposal3ID '3a170000-0000-0000-0000-000000000009'
\set submission1ID '3a170000-0000-0000-0000-000000000010'
\set submission2ID '3a170000-0000-0000-0000-000000000011'
\set submission3ID '3a170000-0000-0000-0000-000000000012'
\set submission4ID '3a170000-0000-0000-0000-000000000013'
\set submission5ID '3a170000-0000-0000-0000-000000000014'
\set user1ID '3a170000-0000-0000-0000-000000000015'
\set user2ID '3a170000-0000-0000-0000-000000000016'
\set user3ID '3a170000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Speaker of the alpha talk
select fx_user(:'user1ID', jsonb_build_object('name', 'Alice'));

-- Speaker of the beta talk
select fx_user(:'user2ID', jsonb_build_object('name', 'Bob'));

-- Speaker of the gamma talk
select fx_user(:'user3ID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

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
        'Alpha talk',
        make_interval(mins => 45),
        'beginner',
        'Alpha Talk',
        :'user1ID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Beta talk',
        make_interval(mins => 60),
        'intermediate',
        'Beta Talk',
        :'user2ID'
    ),
    (
        :'proposal3ID',
        '2024-01-04 00:00:00+00',
        'Gamma talk',
        make_interval(mins => 30),
        'advanced',
        'Gamma Talk',
        :'user3ID'
    );

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that owns none of the events
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

-- Event without approved submissions
select fx_event(:'eventNoApprovedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Event description',
    'published', true
));

-- Deleted event of the owning group
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values
    (:'submission1ID', :'eventID', :'proposal1ID', 'approved'),
    (:'submission2ID', :'eventID', :'proposal2ID', 'approved'),
    (:'submission3ID', :'eventID', :'proposal3ID', 'rejected'),
    (:'submission4ID', :'eventNoApprovedID', :'proposal1ID', 'not-reviewed'),
    (:'submission5ID', :'eventNoApprovedID', :'proposal2ID', 'rejected'),
    (:'deletedEventSubmissionID', :'deletedEventID', :'proposal1ID', 'approved');

-- Label sorted first by name despite its larger identifier
insert into event_label (event_label_id, color, event_id, name)
values (:'labelAlphaID', '#DBEAFE', :'eventID', 'Alpha');

-- Label sorted last by name despite its smaller identifier
insert into event_label (event_label_id, color, event_id, name)
values (:'labelZetaID', '#FEE2E2', :'eventID', 'Zeta');

-- Labels linked to the first approved submission
insert into cfs_submission_label (cfs_submission_id, event_label_id)
values
    (:'submission1ID', :'labelZetaID'),
    (:'submission1ID', :'labelAlphaID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list approved submissions with label IDs ordered by label name
select is(
    list_event_approved_cfs_submissions(:'groupID'::uuid, :'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'cfs_submission_id', :'submission1ID'::uuid,
            'label_ids', jsonb_build_array(:'labelAlphaID'::uuid, :'labelZetaID'::uuid),
            'session_proposal_id', :'proposal1ID'::uuid,
            'speaker_name', 'Alice',
            'title', 'Alpha Talk'
        ),
        jsonb_build_object(
            'cfs_submission_id', :'submission2ID'::uuid,
            'label_ids', '[]'::jsonb,
            'session_proposal_id', :'proposal2ID'::uuid,
            'speaker_name', 'Bob',
            'title', 'Beta Talk'
        )
    ),
    'Should list approved submissions with label IDs ordered by label name'
);

-- Should return empty list for deleted events
select is(
    list_event_approved_cfs_submissions(:'groupID'::uuid, :'deletedEventID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list for deleted events'
);

-- Should return empty list for events outside the group
select is(
    list_event_approved_cfs_submissions(:'otherGroupID'::uuid, :'eventID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list for events outside the group'
);

-- Should return empty list when no submissions are approved
select is(
    list_event_approved_cfs_submissions(:'groupID'::uuid, :'eventNoApprovedID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list when no submissions are approved'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
