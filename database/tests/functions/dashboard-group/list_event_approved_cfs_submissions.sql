-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a170000-0000-0000-0000-000000000001'
\set eventCategoryID '3a170000-0000-0000-0000-000000000002'
\set eventID '3a170000-0000-0000-0000-000000000003'
\set eventNoApprovedID '3a170000-0000-0000-0000-000000000004'
\set groupCategoryID '3a170000-0000-0000-0000-000000000005'
\set groupID '3a170000-0000-0000-0000-000000000006'
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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user3ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('name', 'Alice'));
select fx_user(:'user2ID', jsonb_build_object('name', 'Bob'));

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
    (:'submission5ID', :'eventNoApprovedID', :'proposal2ID', 'rejected');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list approved submissions for sessions
select is(
    list_event_approved_cfs_submissions(:'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'cfs_submission_id', :'submission1ID'::uuid,
            'session_proposal_id', :'proposal1ID'::uuid,
            'speaker_name', 'Alice',
            'title', 'Alpha Talk'
        ),
        jsonb_build_object(
            'cfs_submission_id', :'submission2ID'::uuid,
            'session_proposal_id', :'proposal2ID'::uuid,
            'speaker_name', 'Bob',
            'title', 'Beta Talk'
        )
    ),
    'Should list approved submissions for sessions'
);

-- Should return empty list when no submissions are approved
select is(
    list_event_approved_cfs_submissions(:'eventNoApprovedID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list when no submissions are approved'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
