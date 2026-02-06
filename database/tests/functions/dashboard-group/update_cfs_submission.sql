-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposal2ID '00000000-0000-0000-0000-000000000062'
\set proposal3ID '00000000-0000-0000-0000-000000000063'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set reviewerID '00000000-0000-0000-0000-000000000081'
\set submission2ID '00000000-0000-0000-0000-000000000072'
\set submission3ID '00000000-0000-0000-0000-000000000073'
\set submissionID '00000000-0000-0000-0000-000000000071'
\set userID '00000000-0000-0000-0000-000000000091'

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

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice'),
    (:'reviewerID', gen_random_bytes(32), 'reviewer@example.com', 'reviewer', true, 'Reviewer');

-- Session proposal
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
), (
    :'proposal2ID',
    '2024-01-03 00:00:00+00',
    'Talk about SQL',
    make_interval(mins => 30),
    'beginner',
    'SQL Tuning',
    :'userID'
), (
    :'proposal3ID',
    '2024-01-04 00:00:00+00',
    'Talk about Postgres',
    make_interval(mins => 40),
    'beginner',
    'Postgres Basics',
    :'userID'
);

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values (
    :'eventID',
    :'groupID',
    'Event 1',
    'event-1',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true
);

-- CFS submission
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values
    (:'submissionID', :'eventID', :'proposalID', 'not-reviewed'),
    (:'submission2ID', :'eventID', :'proposal2ID', 'withdrawn'),
    (:'submission3ID', :'eventID', :'proposal3ID', 'approved');

-- Session
insert into session (
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    cfs_submission_id
) values (
    :'eventID',
    'Session 1',
    'in-person',
    '2024-01-02 10:00:00+00',
    '2024-01-02 11:00:00+00',
    :'submission3ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Update submission details
select lives_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submissionID',
        jsonb_build_object(
            'action_required_message', 'Need more info',
            'status_id', 'information-requested'
        )::text
    ),
    'Should update submission details'
);

-- Should update submission status
select is(
    (select status_id from cfs_submission where cfs_submission_id = :'submissionID'::uuid),
    'information-requested',
    'Should update submission status'
);

-- Should store action required message
select is(
    (select action_required_message from cfs_submission where cfs_submission_id = :'submissionID'::uuid),
    'Need more info',
    'Should store action required message'
);

-- Should store reviewer
select is(
    (select reviewed_by from cfs_submission where cfs_submission_id = :'submissionID'::uuid),
    :'reviewerID'::uuid,
    'Should store reviewer'
);

-- Should reject status changes for linked submissions
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submission3ID',
        '{"status_id":"rejected"}'
    ),
    'linked submissions must remain approved',
    'Should reject status changes for linked submissions'
);

-- Should reject withdrawn status updates
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submissionID',
        '{"status_id":"withdrawn"}'
    ),
    'invalid submission status',
    'Should reject withdrawn status updates'
);

-- Should reject updating withdrawn submissions
select throws_ok(
    format(
        $$select update_cfs_submission(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::jsonb
        )$$,
        :'reviewerID',
        :'eventID',
        :'submission2ID',
        '{"status_id":"approved"}'
    ),
    'submission not found',
    'Should reject updating withdrawn submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
