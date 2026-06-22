-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '4a160000-0000-0000-0000-000000000001'
\set eventCategoryID '4a160000-0000-0000-0000-000000000002'
\set eventID '4a160000-0000-0000-0000-000000000003'
\set groupCategoryID '4a160000-0000-0000-0000-000000000004'
\set groupID '4a160000-0000-0000-0000-000000000005'
\set linkedSubmissionID '4a160000-0000-0000-0000-000000000006'
\set proposalID '4a160000-0000-0000-0000-000000000007'
\set proposalRustID '4a160000-0000-0000-0000-000000000008'
\set proposalWithSubmissionID '4a160000-0000-0000-0000-000000000009'
\set user2ID '4a160000-0000-0000-0000-000000000010'
\set userID '4a160000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'session-proposal-alliance',
    'Session Proposal Alliance',
    'Alliance for testing session proposal updates',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

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
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Session Proposal Group', 'proposal-group');

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
    :'proposalRustID',
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
    :'proposalID',
    '2024-01-03 00:00:00+00',
    'Session about Zig',
    make_interval(mins => 60),
    'intermediate',
    'Zig 201',
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
    '2024-01-04 00:00:00+00',
    'Session about Python',
    make_interval(mins => 30),
    'beginner',
    'Python 101',
    :'userID'
);

-- CFS submission
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'linkedSubmissionID', :'eventID', :'proposalID'::uuid, 'approved');

-- CFS submission
insert into cfs_submission (event_id, session_proposal_id, status_id)
values (:'eventID', :'proposalWithSubmissionID'::uuid, 'not-reviewed');

-- Session
insert into session (
    cfs_submission_id,
    event_id,
    name,
    session_kind_id,
    starts_at
) values (
    :'linkedSubmissionID',
    :'eventID',
    'Linked Session',
    'in-person',
    current_timestamp + interval '7 days'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Update session proposal
select lives_ok(
    format(
        'select update_session_proposal(%L::uuid, %L::uuid, %L::jsonb)',
        :'userID',
        :'proposalRustID',
        jsonb_build_object(
            'co_speaker_user_id', :'user2ID'::uuid,
            'description', 'Updated description',
            'duration_minutes', 60,
            'session_proposal_level_id', 'intermediate',
            'title', 'Rust 102'
        )::text
    ),
    'Should execute update_session_proposal successfully'
);

-- Should update session proposal
select is(
    (
        select jsonb_build_object(
            'co_speaker_user_id', co_speaker_user_id,
            'description', description,
            'duration', duration,
            'session_proposal_level_id', session_proposal_level_id,
            'status_id', session_proposal_status_id,
            'title', title,
            'user_id', user_id
        )
        from session_proposal
        where session_proposal_id = :'proposalRustID'::uuid
    ),
    jsonb_build_object(
        'co_speaker_user_id', :'user2ID'::uuid,
        'description', 'Updated description',
        'duration', make_interval(mins => 60),
        'session_proposal_level_id', 'intermediate',
        'status_id', 'pending-co-speaker-response',
        'title', 'Rust 102',
        'user_id', :'userID'::uuid
    ),
    'Should persist updated session proposal fields'
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
            select
                'session_proposal_updated',
                %L::uuid,
                'alice',
                'session_proposal',
                session_proposal_id
            from session_proposal
            where title = 'Rust 102'
        $$,
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should clear co-speaker when updated to null
select lives_ok(
    format(
        'select update_session_proposal(%L::uuid, %L::uuid, %L::jsonb)',
        :'userID',
        :'proposalRustID',
        jsonb_build_object(
            'co_speaker_user_id', null,
            'description', 'Updated description',
            'duration_minutes', 60,
            'session_proposal_level_id', 'intermediate',
            'title', 'Rust 102'
        )::text
    ),
    'Should execute update_session_proposal with null co-speaker successfully'
);

-- Should clear co-speaker user id
select is(
    (select co_speaker_user_id from session_proposal where session_proposal_id = :'proposalRustID'::uuid),
    null,
    'Should clear co-speaker user id'
);

-- Should reject changing co-speaker for proposals with submissions
select throws_ok(
    format(
        'select update_session_proposal(%L::uuid, %L::uuid, %L::jsonb)',
        :'userID',
        :'proposalWithSubmissionID',
        jsonb_build_object(
            'co_speaker_user_id', :'user2ID'::uuid,
            'description', 'Updated description',
            'duration_minutes', 45,
            'session_proposal_level_id', 'beginner',
            'title', 'Python 102'
        )::text
    ),
    'session proposal with submissions cannot change co-speaker',
    'Should reject changing co-speaker for proposals with submissions'
);

-- Should reject updating proposals linked to sessions
select throws_ok(
    format(
        'select update_session_proposal(%L::uuid, %L::uuid, %L::jsonb)',
        :'userID',
        :'proposalID',
        jsonb_build_object(
            'co_speaker_user_id', null,
            'description', 'Updated description',
            'duration_minutes', 60,
            'session_proposal_level_id', 'advanced',
            'title', 'Zig 202'
        )::text
    ),
    'session proposal linked to a session',
    'Should reject updating proposals linked to sessions'
);

-- Should not leak linked sessions for other users
select throws_ok(
    format(
        'select update_session_proposal(%L::uuid, %L::uuid, %L::jsonb)',
        :'user2ID',
        :'proposalID',
        jsonb_build_object(
            'co_speaker_user_id', null,
            'description', 'Updated description',
            'duration_minutes', 60,
            'session_proposal_level_id', 'advanced',
            'title', 'Zig 202'
        )::text
    ),
    'session proposal not found',
    'Should not leak linked sessions for other users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
