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
\set userID '00000000-0000-0000-0000-000000000071'
\set user2ID '00000000-0000-0000-0000-000000000072'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
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
returning session_proposal_id as proposal_rust_id \gset

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
    'Session about Zig',
    make_interval(mins => 60),
    'intermediate',
    'Zig 201',
    :'userID'
)
returning session_proposal_id as proposal_id \gset

-- CFS submission
insert into cfs_submission (event_id, session_proposal_id, status_id)
values (:'eventID', :'proposal_id'::uuid, 'approved')
returning cfs_submission_id as linked_submission_id \gset

-- Session
insert into session (
    cfs_submission_id,
    event_id,
    name,
    session_kind_id,
    starts_at
) values (
    :'linked_submission_id',
    :'eventID',
    'Linked Session',
    'in-person',
    current_timestamp + interval '7 days'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Update session proposal
select update_session_proposal(
    :'userID'::uuid,
    :'proposal_rust_id'::uuid,
    jsonb_build_object(
        'co_speaker_user_id', :'user2ID'::uuid,
        'description', 'Updated description',
        'duration_minutes', 60,
        'session_proposal_level_id', 'intermediate',
        'title', 'Rust 102'
    )
);

-- Should update session proposal
select is(
    (
        select jsonb_build_object(
            'co_speaker_user_id', co_speaker_user_id,
            'description', description,
            'duration', duration,
            'session_proposal_level_id', session_proposal_level_id,
            'title', title,
            'user_id', user_id
        )
        from session_proposal
        where session_proposal_id = :'proposal_rust_id'::uuid
    ),
    jsonb_build_object(
        'co_speaker_user_id', :'user2ID'::uuid,
        'description', 'Updated description',
        'duration', make_interval(mins => 60),
        'session_proposal_level_id', 'intermediate',
        'title', 'Rust 102',
        'user_id', :'userID'::uuid
    ),
    'Should update session proposal'
);

-- Should reject updating proposals linked to sessions
select throws_ok(
    format(
        'select update_session_proposal(%L::uuid, %L::uuid, %L::jsonb)',
        :'userID',
        :'proposal_id',
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
        :'proposal_id',
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
