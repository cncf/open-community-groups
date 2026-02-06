-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000072'
\set userID '00000000-0000-0000-0000-000000000071'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'bob', true, 'Bob');

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
    gen_random_uuid(),
    '2024-01-02 00:00:00+00',
    'Session about Rust',
    make_interval(mins => 45),
    'beginner',
    'Rust 101',
    :'userID'
)
returning session_proposal_id as "sessionProposalID" \gset

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
    gen_random_uuid(),
    '2024-01-03 00:00:00+00',
    'Session about Go',
    make_interval(mins => 45),
    'beginner',
    'Go 101',
    :'userID'
)
returning session_proposal_id as "proposalWithSubmissionID" \gset

-- CFS submission
insert into cfs_submission (event_id, session_proposal_id, status_id)
values (:'eventID', :'proposalWithSubmissionID'::uuid, 'not-reviewed');

-- Session proposal (other user)
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    gen_random_uuid(),
    '2024-01-04 00:00:00+00',
    'Session about Python',
    make_interval(mins => 45),
    'beginner',
    'Python 101',
    :'user2ID'
)
returning session_proposal_id as "otherUserProposalID" \gset

-- CFS submission (other user)
insert into cfs_submission (event_id, session_proposal_id, status_id)
values (:'eventID', :'otherUserProposalID'::uuid, 'not-reviewed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Delete session proposal
select lives_ok(
    format(
        'select delete_session_proposal(%L::uuid, %L::uuid)',
        :'userID',
        :'sessionProposalID'
    ),
    'Should execute delete_session_proposal successfully'
);

-- Should delete session proposal
select is(
    (select count(*) from session_proposal where session_proposal_id = :'sessionProposalID'::uuid),
    0::bigint,
    'Should remove session proposal record'
);

-- Should reject deleting proposals with submissions
select throws_ok(
    format(
        'select delete_session_proposal(%L::uuid, %L::uuid)',
        :'userID',
        :'proposalWithSubmissionID'
    ),
    'session proposal has submissions',
    'Should reject deleting proposals with submissions'
);

-- Should not leak linked sessions for other users
select throws_ok(
    format(
        'select delete_session_proposal(%L::uuid, %L::uuid)',
        :'userID',
        :'otherUserProposalID'
    ),
    'session proposal not found',
    'Should not leak submissions for other users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
