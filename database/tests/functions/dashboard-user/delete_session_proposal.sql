-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a060000-0000-0000-0000-000000000001'
\set eventCategoryID '4a060000-0000-0000-0000-000000000002'
\set eventID '4a060000-0000-0000-0000-000000000003'
\set groupCategoryID '4a060000-0000-0000-0000-000000000004'
\set groupID '4a060000-0000-0000-0000-000000000005'
\set otherUserProposalID '4a060000-0000-0000-0000-000000000006'
\set proposalWithSubmissionID '4a060000-0000-0000-0000-000000000007'
\set sessionProposalID '4a060000-0000-0000-0000-000000000008'
\set user2ID '4a060000-0000-0000-0000-000000000009'
\set userID '4a060000-0000-0000-0000-000000000010'

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
    'session-proposal-community',
    'Session Proposal Community',
    'Community for testing session proposal deletion',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

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
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    'Bob'
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Session Proposal Group', 'proposal-group');

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
    :'sessionProposalID',
    '2024-01-02 00:00:00+00',
    'Session about Rust',
    make_interval(mins => 45),
    'beginner',
    'Rust 101',
    :'userID'
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
    :'proposalWithSubmissionID',
    '2024-01-03 00:00:00+00',
    'Session about Go',
    make_interval(mins => 45),
    'beginner',
    'Go 101',
    :'userID'
);

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
    :'otherUserProposalID',
    '2024-01-04 00:00:00+00',
    'Session about Python',
    make_interval(mins => 45),
    'beginner',
    'Python 101',
    :'user2ID'
);

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

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'session_proposal_deleted',
            %L::uuid,
            'alice',
            'session_proposal',
            %L::uuid
        )
        $$,
        :'userID',
        :'sessionProposalID'
    ),
    'Should create the expected audit row'
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
