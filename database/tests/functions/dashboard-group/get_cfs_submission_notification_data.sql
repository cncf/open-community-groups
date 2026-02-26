-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set submissionID '00000000-0000-0000-0000-000000000071'
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
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice');

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
    status_id,
    action_required_message
) values (
    :'submissionID',
    :'eventID',
    :'proposalID',
    'information-requested',
    'Need more info'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return submission notification data
select is(
    get_cfs_submission_notification_data(:'eventID'::uuid, :'submissionID'::uuid)::jsonb,
    jsonb_build_object(
        'action_required_message', 'Need more info',
        'status_id', 'information-requested',
        'status_name', 'Information requested',
        'user_id', :'userID'::uuid
    ),
    'Should return submission notification data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
