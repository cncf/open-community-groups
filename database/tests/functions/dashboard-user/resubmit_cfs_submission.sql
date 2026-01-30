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
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposal1ID '00000000-0000-0000-0000-000000000061'
\set proposal2ID '00000000-0000-0000-0000-000000000062'
\set submission1ID '00000000-0000-0000-0000-000000000071'
\set submission2ID '00000000-0000-0000-0000-000000000072'
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
        :'proposal1ID',
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
    published,
    cfs_description,
    cfs_enabled,
    cfs_starts_at,
    cfs_ends_at,
    starts_at,
    ends_at
) values (
    :'eventID',
    :'groupID',
    'Event 1',
    'event-1',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    'CFS open',
    true,
    current_timestamp - interval '1 day',
    current_timestamp + interval '1 day',
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message
) values
    (
        :'submission1ID',
        :'eventID',
        :'proposal1ID',
        'information-requested',
        'Need more info'
    ),
    (
        :'submission2ID',
        :'eventID',
        :'proposal2ID',
        'approved',
        null
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Resubmit submission
select resubmit_cfs_submission(:'userID'::uuid, :'submission1ID'::uuid);

-- Should resubmit submission
select is(
    (select status_id from cfs_submission where cfs_submission_id = :'submission1ID'::uuid),
    'not-reviewed',
    'Should resubmit submission'
);

-- Should clear action required message
select is(
    (select action_required_message from cfs_submission where cfs_submission_id = :'submission1ID'::uuid),
    null,
    'Should clear action required message'
);

-- Should reject resubmitting approved submission
select throws_ok(
    format(
        'select resubmit_cfs_submission(%L::uuid, %L::uuid)',
        :'userID',
        :'submission2ID'
    ),
    'submission not found or cannot be resubmitted',
    'Should reject resubmitting approved submission'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
