-- Tests projecting the shared session proposal JSON fields.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set coSpeakerID '3e810000-0000-0000-0000-000000000001'
\set proposalCoSpeakerID '3e810000-0000-0000-0000-000000000002'
\set proposalFractionalID '3e810000-0000-0000-0000-000000000003'
\set proposalID '3e810000-0000-0000-0000-000000000004'
\set speakerID '3e810000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Co-speaker embedded in the co-speaker proposal
select fx_user(:'coSpeakerID', jsonb_build_object(
    'name', 'Co Speaker',
    'username', 'session-proposal-json-co-speaker'
));

-- Speaker owning every proposal
select fx_user(:'speakerID');

-- Proposal with a co-speaker
insert into session_proposal (
    session_proposal_id,
    co_speaker_user_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalCoSpeakerID',
    :'coSpeakerID',
    'Proposal with a co-speaker',
    make_interval(mins => 30),
    'beginner',
    'Pairing on Rust',
    :'speakerID'
);

-- Proposal whose duration is not a whole number of minutes
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalFractionalID',
    'Proposal with a fractional duration',
    make_interval(mins => 90, secs => 30),
    'advanced',
    'Long Rust Workshop',
    :'speakerID'
);

-- Proposal without a co-speaker
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalID',
    'Proposal without a co-speaker',
    make_interval(mins => 45),
    'intermediate',
    'Rust Ownership',
    :'speakerID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should embed the co-speaker summary
select is(
    (
        select session_proposal_json(sp) -> 'co_speaker'
        from session_proposal sp
        where sp.session_proposal_id = :'proposalCoSpeakerID'::uuid
    ),
    jsonb_build_object(
        'user_id', :'coSpeakerID'::uuid,
        'username', 'session-proposal-json-co-speaker',

        'name', 'Co Speaker'
    ),
    'Should embed the co-speaker summary'
);

-- Should project the proposal fields with the level display name
select is(
    (
        select session_proposal_json(sp) - 'co_speaker'
        from session_proposal sp
        where sp.session_proposal_id = :'proposalID'::uuid
    ),
    jsonb_build_object(
        'description', 'Proposal without a co-speaker',
        'duration_minutes', 45,
        'session_proposal_id', :'proposalID'::uuid,
        'session_proposal_level_id', 'intermediate',
        'session_proposal_level_name', 'Intermediate',
        'title', 'Rust Ownership'
    ),
    'Should project the proposal fields with the level display name'
);

-- Should return an explicit null co_speaker without a co-speaker
select is(
    (
        select jsonb_typeof(session_proposal_json(sp) -> 'co_speaker')
        from session_proposal sp
        where sp.session_proposal_id = :'proposalID'::uuid
    ),
    'null',
    'Should return an explicit null co_speaker without a co-speaker'
);

-- Should round the duration down to whole minutes
select is(
    (
        select (session_proposal_json(sp) ->> 'duration_minutes')::int
        from session_proposal sp
        where sp.session_proposal_id = :'proposalFractionalID'::uuid
    ),
    90,
    'Should round the duration down to whole minutes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
