-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set eventNoApprovedID '00000000-0000-0000-0000-000000000052'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposal1ID '00000000-0000-0000-0000-000000000061'
\set proposal2ID '00000000-0000-0000-0000-000000000062'
\set proposal3ID '00000000-0000-0000-0000-000000000063'
\set submission1ID '00000000-0000-0000-0000-000000000071'
\set submission2ID '00000000-0000-0000-0000-000000000072'
\set submission3ID '00000000-0000-0000-0000-000000000073'
\set submission4ID '00000000-0000-0000-0000-000000000074'
\set submission5ID '00000000-0000-0000-0000-000000000075'
\set user1ID '00000000-0000-0000-0000-000000000081'
\set user2ID '00000000-0000-0000-0000-000000000082'
\set user3ID '00000000-0000-0000-0000-000000000083'

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
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true, 'Bob'),
    (:'user3ID', gen_random_bytes(32), 'carol@example.com', 'carol', true, 'Carol');

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
    :'eventNoApprovedID',
    :'groupID',
    'Event 2',
    'event-2',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true
);

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
