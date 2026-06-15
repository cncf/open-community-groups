-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set coSpeakerUserID '4a050000-0000-0000-0000-000000000001'
\set userID '4a050000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

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
    :'coSpeakerUserID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    'Bob'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should store proposal details
select lives_ok(
    format(
        $$
            select add_session_proposal(
                %L::uuid,
                jsonb_build_object(
                    'co_speaker_user_id', %L::uuid,
                    'description', 'Session about Rust',
                    'duration_minutes', 45,
                    'session_proposal_level_id', 'beginner',
                    'title', 'Rust 101'
                )
            )
        $$,
        :'userID',
        :'coSpeakerUserID'
    ),
    'Should add a session proposal with a co-speaker'
);
select session_proposal_id as "sessionProposalID"
from session_proposal
where title = 'Rust 101' \gset

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
        where session_proposal_id = :'sessionProposalID'::uuid
    ),
    jsonb_build_object(
        'co_speaker_user_id', :'coSpeakerUserID'::uuid,
        'description', 'Session about Rust',
        'duration', make_interval(mins => 45),
        'session_proposal_level_id', 'beginner',
        'status_id', 'pending-co-speaker-response',
        'title', 'Rust 101',
        'user_id', :'userID'::uuid
    ),
    'Should store proposal details'
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
                'session_proposal_added',
                %L::uuid,
                'alice',
                'session_proposal',
                session_proposal_id
            from session_proposal
            where title = 'Rust 101'
        $$,
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should set ready-for-submission when no co-speaker is provided
select lives_ok(
    format(
        $$
            select add_session_proposal(
                %L::uuid,
                jsonb_build_object(
                    'description', 'Session without co-speaker',
                    'duration_minutes', 30,
                    'session_proposal_level_id', 'intermediate',
                    'title', 'Rust Solo'
                )
            )
        $$,
        :'userID'
    ),
    'Should add a session proposal without a co-speaker'
);
select session_proposal_id as "sessionProposalNoCoSpeakerID"
from session_proposal
where title = 'Rust Solo' \gset

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
        where session_proposal_id = :'sessionProposalNoCoSpeakerID'::uuid
    ),
    jsonb_build_object(
        'co_speaker_user_id', null,
        'description', 'Session without co-speaker',
        'duration', make_interval(mins => 30),
        'session_proposal_level_id', 'intermediate',
        'status_id', 'ready-for-submission',
        'title', 'Rust Solo',
        'user_id', :'userID'::uuid
    ),
    'Should set ready-for-submission when no co-speaker is provided'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
