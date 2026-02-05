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
\set eventEmptyID '00000000-0000-0000-0000-000000000052'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set proposal2ID '00000000-0000-0000-0000-000000000062'
\set proposal3ID '00000000-0000-0000-0000-000000000063'
\set submissionID '00000000-0000-0000-0000-000000000071'
\set submission2ID '00000000-0000-0000-0000-000000000072'
\set submission3ID '00000000-0000-0000-0000-000000000073'
\set reviewerID '00000000-0000-0000-0000-000000000083'
\set sessionID '00000000-0000-0000-0000-000000000091'
\set userID '00000000-0000-0000-0000-000000000081'
\set user2ID '00000000-0000-0000-0000-000000000082'

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
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, null),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true, null),
    (:'reviewerID', gen_random_bytes(32), 'reviewer@example.com', 'reviewer', true, null);

-- Session proposal
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
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'user2ID'
    ),
    (
        :'proposal3ID',
        '2024-01-04 00:00:00+00',
        'Talk about SQL',
        make_interval(mins => 30),
        'beginner',
        'SQL Tuning',
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

-- Event (empty)
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
    :'eventEmptyID',
    :'groupID',
    'Event 2',
    'event-2',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true
);

-- CFS submission
insert into cfs_submission (
    cfs_submission_id,
    created_at,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message,
    reviewed_by,
    updated_at
) values
    (
        :'submissionID',
        '2024-01-04 00:00:00+00',
        :'eventID',
        :'proposalID',
        'not-reviewed',
        null,
        null,
        '2024-02-01 00:00:00+00'
    ),
    (
        :'submission2ID',
        '2024-01-05 00:00:00+00',
        :'eventID',
        :'proposal2ID',
        'approved',
        'Looks good',
        :'reviewerID',
        '2024-01-06 00:00:00+00'
    ),
    (
        :'submission3ID',
        '2024-01-06 00:00:00+00',
        :'eventID',
        :'proposal3ID',
        'withdrawn',
        null,
        null,
        '2024-01-07 00:00:00+00'
    );

-- Session
insert into session (
    session_id,
    cfs_submission_id,
    event_id,
    name,
    session_kind_id,
    starts_at
) values (
    :'sessionID',
    :'submission2ID',
    :'eventID',
    'Session 1',
    'in-person',
    '2024-02-01 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list event submissions
select is(
    list_event_cfs_submissions(:'eventID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', jsonb_build_array(
            jsonb_build_object(
                'action_required_message', null,
                'cfs_submission_id', :'submissionID'::uuid,
                'created_at', (select extract(epoch from created_at)::bigint from cfs_submission
                    where cfs_submission_id = :'submissionID'::uuid),
                'linked_session_id', null,
                'session_proposal', jsonb_build_object(
                    'description', 'Talk about Rust',
                    'duration_minutes', 45,
                    'session_proposal_id', :'proposalID'::uuid,
                    'session_proposal_level_id', 'beginner',
                    'session_proposal_level_name', 'Beginner',
                    'title', 'Rust Intro'
                ),
                'reviewed_by', null,
                'speaker', jsonb_build_object(
                    'user_id', :'userID'::uuid,
                    'username', 'alice'
                ),
                'status_id', 'not-reviewed',
                'status_name', 'Not reviewed',
                'updated_at', (select extract(epoch from updated_at)::bigint from cfs_submission
                    where cfs_submission_id = :'submissionID'::uuid)
            ),
            jsonb_build_object(
                'action_required_message', 'Looks good',
                'cfs_submission_id', :'submission2ID'::uuid,
                'created_at', (select extract(epoch from created_at)::bigint from cfs_submission
                    where cfs_submission_id = :'submission2ID'::uuid),
                'linked_session_id', :'sessionID'::uuid,
                'session_proposal', jsonb_build_object(
                    'description', 'Talk about Go',
                    'duration_minutes', 60,
                    'session_proposal_id', :'proposal2ID'::uuid,
                    'session_proposal_level_id', 'intermediate',
                    'session_proposal_level_name', 'Intermediate',
                    'title', 'Go Intro'
                ),
                'reviewed_by', jsonb_build_object(
                    'user_id', :'reviewerID'::uuid,
                    'username', 'reviewer'
                ),
                'speaker', jsonb_build_object(
                    'user_id', :'user2ID'::uuid,
                    'username', 'bob'
                ),
                'status_id', 'approved',
                'status_name', 'Approved',
                'updated_at', (select extract(epoch from updated_at)::bigint from cfs_submission
                    where cfs_submission_id = :'submission2ID'::uuid)
            )
        ),
        'total', 2
    ),
    'Should list event submissions'
);

-- Should paginate submissions
select is(
    list_event_cfs_submissions(:'eventID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', jsonb_build_array(jsonb_build_object(
            'action_required_message', 'Looks good',
            'cfs_submission_id', :'submission2ID'::uuid,
            'created_at', (select extract(epoch from created_at)::bigint from cfs_submission
                where cfs_submission_id = :'submission2ID'::uuid),
            'linked_session_id', :'sessionID'::uuid,
            'session_proposal', jsonb_build_object(
                'description', 'Talk about Go',
                'duration_minutes', 60,
                'session_proposal_id', :'proposal2ID'::uuid,
                'session_proposal_level_id', 'intermediate',
                'session_proposal_level_name', 'Intermediate',
                'title', 'Go Intro'
            ),
            'reviewed_by', jsonb_build_object(
                'user_id', :'reviewerID'::uuid,
                'username', 'reviewer'
            ),
            'speaker', jsonb_build_object(
                'user_id', :'user2ID'::uuid,
                'username', 'bob'
            ),
            'status_id', 'approved',
            'status_name', 'Approved',
            'updated_at', (select extract(epoch from updated_at)::bigint from cfs_submission
                where cfs_submission_id = :'submission2ID'::uuid)
        )),
        'total', 2
    ),
    'Should paginate submissions'
);

-- Should return empty submissions for events without submissions
select is(
    list_event_cfs_submissions(:'eventEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for events without submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
