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
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposalRustID '00000000-0000-0000-0000-000000000061'
\set proposalZigID '00000000-0000-0000-0000-000000000062'
\set submissionID '00000000-0000-0000-0000-000000000071'
\set userID '00000000-0000-0000-0000-000000000081'
\set userEmptyID '00000000-0000-0000-0000-000000000099'

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
        :'proposalRustID',
        '2024-01-02 00:00:00+00',
        'Talk about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust Intro',
        :'userID'
    ),
    (
        :'proposalZigID',
        '2024-01-03 00:00:00+00',
        'Talk about Zig',
        make_interval(mins => 60),
        'intermediate',
        'Zig Intro',
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
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values (
    :'submissionID',
    :'eventID',
    :'proposalZigID',
    'not-reviewed'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list proposals with submission status for event
select is(
    list_user_session_proposals_for_cfs_event(:'userID'::uuid, :'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'created_at', 1704240000,
            'description', 'Talk about Zig',
            'duration_minutes', 60,
            'is_submitted', true,
            'session_proposal_id', :'proposalZigID'::uuid,
            'session_proposal_level_id', 'intermediate',
            'session_proposal_level_name', 'Intermediate',
            'submission_status_id', 'not-reviewed',
            'submission_status_name', 'Not reviewed',
            'title', 'Zig Intro'
        ),
        jsonb_build_object(
            'created_at', 1704153600,
            'description', 'Talk about Rust',
            'duration_minutes', 45,
            'is_submitted', false,
            'session_proposal_id', :'proposalRustID'::uuid,
            'session_proposal_level_id', 'beginner',
            'session_proposal_level_name', 'Beginner',
            'title', 'Rust Intro'
        )
    ),
    'Should list proposals with submission status for event'
);

-- Should return empty list for users without proposals
select is(
    list_user_session_proposals_for_cfs_event(:'userEmptyID'::uuid, :'eventID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list for users without proposals'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
