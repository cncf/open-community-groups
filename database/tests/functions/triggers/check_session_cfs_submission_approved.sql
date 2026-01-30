-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set event2ID '00000000-0000-0000-0000-000000000052'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set proposalPendingID '00000000-0000-0000-0000-000000000062'
\set submissionApprovedID '00000000-0000-0000-0000-000000000071'
\set submissionOtherEventID '00000000-0000-0000-0000-000000000072'
\set submissionPendingID '00000000-0000-0000-0000-000000000073'
\set userID '00000000-0000-0000-0000-000000000081'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

-- Event category
insert into event_category (event_category_id, community_id, name, slug) values
    (:'eventCategoryID', :'communityID', 'Meetup', 'meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice');

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
    );

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at
) values
    (:'eventID', :'groupID', 'Event 1', 'event-1', 'Event description', 'UTC', :'eventCategoryID', 'in-person', '2025-01-10 10:00:00+00', '2025-01-10 12:00:00+00'),
    (:'event2ID', :'groupID', 'Event 2', 'event-2', 'Event description', 'UTC', :'eventCategoryID', 'in-person', '2025-01-11 10:00:00+00', '2025-01-11 12:00:00+00');

-- CFS submissions
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id) values
    (:'submissionApprovedID', :'eventID', :'proposalID', 'approved'),
    (:'submissionPendingID', :'eventID', :'proposalPendingID', 'not-reviewed'),
    (:'submissionOtherEventID', :'event2ID', :'proposalID', 'approved');

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
