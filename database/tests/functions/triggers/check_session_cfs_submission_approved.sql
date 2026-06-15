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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cfs-submission-community',
    'CFS Submission Community',
    'A community for CFS submission trigger tests',
    'https://example.com/cfs-banner-mobile.png',
    'https://example.com/cfs-banner.png',
    'https://example.com/cfs-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, name, username)
values (:'userID', gen_random_bytes(32), 'alice@example.com', true, 'Alice', 'alice');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'CFS Submission Group',
    'cfs-submission-group'
);

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
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    starts_at,
    ends_at,
    timezone
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event 1',
    'event-1',
    'Event description',
    '2025-01-10 10:00:00+00',
    '2025-01-10 12:00:00+00',
    'UTC'
), (
    :'event2ID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event 2',
    'event-2',
    'Event description',
    '2025-01-11 10:00:00+00',
    '2025-01-11 12:00:00+00',
    'UTC'
);

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
