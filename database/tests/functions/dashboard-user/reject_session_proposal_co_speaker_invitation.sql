-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set coSpeakerUserID '00000000-0000-0000-0000-000000000071'
\set proposalPendingID '00000000-0000-0000-0000-000000000081'
\set proposalReadyID '00000000-0000-0000-0000-000000000082'
\set speakerUserID '00000000-0000-0000-0000-000000000072'
\set userID2 '00000000-0000-0000-0000-000000000073'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (auth_hash, email, email_verified, user_id, username) values
    ('hash-1', 'co-speaker@example.com', true, :'coSpeakerUserID', 'co-speaker'),
    ('hash-2', 'speaker@example.com', true, :'speakerUserID', 'speaker'),
    ('hash-3', 'user2@example.com', true, :'userID2', 'user2');

-- Session proposals
insert into session_proposal (
    co_speaker_user_id,
    description,
    duration,
    session_proposal_id,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    user_id
) values
    (
        :'coSpeakerUserID',
        'Pending proposal',
        make_interval(mins => 45),
        :'proposalPendingID',
        'beginner',
        'pending-co-speaker-response',
        'Pending proposal',
        :'speakerUserID'
    ),
    (
        :'coSpeakerUserID',
        'Ready proposal',
        make_interval(mins => 45),
        :'proposalReadyID',
        'beginner',
        'ready-for-submission',
        'Ready proposal',
        :'speakerUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should execute rejection for pending invitation
select lives_ok(
    format(
        'select reject_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid)',
        :'coSpeakerUserID',
        :'proposalPendingID'
    ),
    'Should execute rejection for pending invitation'
);

-- Should set proposal status to declined after rejection
select is(
    (
        select session_proposal_status_id
        from session_proposal
        where session_proposal_id = :'proposalPendingID'::uuid
    ),
    'declined-by-co-speaker',
    'Should set proposal status to declined after rejection'
);

-- Should reject rejection when invitation is not pending
select throws_ok(
    format(
        'select reject_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid)',
        :'coSpeakerUserID',
        :'proposalReadyID'
    ),
    'session proposal is not awaiting co-speaker response',
    'Should reject rejection when invitation is not pending'
);

-- Should reject rejection for users that are not the invited co-speaker
select throws_ok(
    format(
        'select reject_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid)',
        :'userID2',
        :'proposalReadyID'
    ),
    'session proposal invitation not found',
    'Should reject rejection for users that are not the invited co-speaker'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
