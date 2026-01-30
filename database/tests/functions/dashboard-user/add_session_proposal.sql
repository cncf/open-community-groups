-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userID '00000000-0000-0000-0000-000000000071'
\set coSpeakerUserID '00000000-0000-0000-0000-000000000072'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice'),
    (:'coSpeakerUserID', gen_random_bytes(32), 'bob@example.com', 'bob', true, 'Bob');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Create session proposal
select add_session_proposal(
    :'userID'::uuid,
    jsonb_build_object(
        'co_speaker_user_id', :'coSpeakerUserID'::uuid,
        'description', 'Session about Rust',
        'duration_minutes', 45,
        'session_proposal_level_id', 'beginner',
        'title', 'Rust 101'
    )
) as session_proposal_id \gset

-- Should store proposal details
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
        where session_proposal_id = :'session_proposal_id'::uuid
    ),
    jsonb_build_object(
        'co_speaker_user_id', :'coSpeakerUserID'::uuid,
        'description', 'Session about Rust',
        'duration', make_interval(mins => 45),
        'session_proposal_level_id', 'beginner',
        'title', 'Rust 101',
        'user_id', :'userID'::uuid
    ),
    'Should store proposal details'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
