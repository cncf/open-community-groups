-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0e0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a0e0000-0000-0000-0000-000000000002'
\set eventID '3a0e0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a0e0000-0000-0000-0000-000000000004'
\set groupID '3a0e0000-0000-0000-0000-000000000005'
\set proposalID '3a0e0000-0000-0000-0000-000000000006'
\set submissionID '3a0e0000-0000-0000-0000-000000000007'
\set userID '3a0e0000-0000-0000-0000-000000000008'

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
    'rust-community',
    'Rust Community',
    'A community for Rust events',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'userID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice'
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Rust Group', 'rust-group');

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
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    published
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Rust Meetup',
    'rust-meetup',
    'Event description',
    'UTC',
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
