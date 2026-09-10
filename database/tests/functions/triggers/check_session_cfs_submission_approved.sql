-- Tests linking approved CFS submissions to event sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab070000-0000-0000-0000-000000000001'
\set event2ID 'ab070000-0000-0000-0000-000000000002'
\set eventCategoryID 'ab070000-0000-0000-0000-000000000003'
\set eventID 'ab070000-0000-0000-0000-000000000004'
\set groupCategoryID 'ab070000-0000-0000-0000-000000000005'
\set groupID 'ab070000-0000-0000-0000-000000000006'
\set proposalApprovedUpdateID 'ab070000-0000-0000-0000-000000000007'
\set proposalID 'ab070000-0000-0000-0000-000000000008'
\set proposalPendingID 'ab070000-0000-0000-0000-000000000009'
\set sessionID 'ab070000-0000-0000-0000-000000000010'
\set submissionApprovedID 'ab070000-0000-0000-0000-000000000011'
\set submissionApprovedUpdateID 'ab070000-0000-0000-0000-000000000012'
\set submissionOtherEventID 'ab070000-0000-0000-0000-000000000013'
\set submissionPendingID 'ab070000-0000-0000-0000-000000000014'
\set userID 'ab070000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
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
        :'proposalID',
        '2024-01-02 00:00:00+00',
        'Talk about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust Intro',
        :'userID'
    ),
    (
        :'proposalPendingID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'userID'
    ),
    (
        :'proposalApprovedUpdateID',
        '2024-01-04 00:00:00+00',
        'Talk about Zig',
        make_interval(mins => 30),
        'beginner',
        'Zig Intro',
        :'userID'
    );

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-10 12:00:00+00',
    'starts_at', '2025-01-10 10:00:00+00'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-11 12:00:00+00',
    'starts_at', '2025-01-11 10:00:00+00'
));

-- CFS submissions
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id) values
    (:'submissionApprovedID', :'eventID', :'proposalID', 'approved'),
    (:'submissionApprovedUpdateID', :'eventID', :'proposalApprovedUpdateID', 'approved'),
    (:'submissionOtherEventID', :'event2ID', :'proposalID', 'approved'),
    (:'submissionPendingID', :'eventID', :'proposalPendingID', 'not-reviewed');

-- Session
insert into session (session_id, event_id, name, session_kind_id, starts_at, ends_at)
values (
    :'sessionID',
    :'eventID',
    'Existing Session',
    'in-person',
    '2025-01-10 10:00:00+00',
    '2025-01-10 10:30:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow linking approved submission
select lives_ok(
    format(
        'insert into session (event_id, name, session_kind_id, starts_at, ends_at, cfs_submission_id) values (%L, %L, %L, %L, %L, %L)',
        :'eventID',
        'Session 1',
        'in-person',
        '2025-01-10 10:30:00+00',
        '2025-01-10 11:30:00+00',
        :'submissionApprovedID'
    ),
    'Should allow linking approved submission'
);

-- Should reject non-approved submissions
select throws_ok(
    format(
        'insert into session (event_id, name, session_kind_id, starts_at, ends_at, cfs_submission_id) values (%L, %L, %L, %L, %L, %L)',
        :'eventID',
        'Session 2',
        'in-person',
        '2025-01-10 10:30:00+00',
        '2025-01-10 11:30:00+00',
        :'submissionPendingID'
    ),
    'OCG01',
    'cfs submission must be approved',
    'Should reject non-approved submissions'
);

-- Should reject submissions from another event
select throws_ok(
    format(
        'insert into session (event_id, name, session_kind_id, starts_at, ends_at, cfs_submission_id) values (%L, %L, %L, %L, %L, %L)',
        :'eventID',
        'Session 3',
        'in-person',
        '2025-01-10 10:30:00+00',
        '2025-01-10 11:30:00+00',
        :'submissionOtherEventID'
    ),
    'OCG01',
    'cfs submission does not belong to the session event',
    'Should reject submissions from another event'
);

-- Should reject updating sessions to non-approved submissions
select throws_ok(
    format(
        'update session set cfs_submission_id = %L where session_id = %L',
        :'submissionPendingID',
        :'sessionID'
    ),
    'OCG01',
    'cfs submission must be approved',
    'Should reject updating sessions to non-approved submissions'
);

-- Should allow updating sessions to approved submissions
select lives_ok(
    format(
        'update session set cfs_submission_id = %L where session_id = %L',
        :'submissionApprovedUpdateID',
        :'sessionID'
    ),
    'Should allow updating sessions to approved submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
