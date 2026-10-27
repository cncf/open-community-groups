-- Tests recording a co-speaker's response to a session proposal invitation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set coSpeakerUserID '3e820000-0000-0000-0000-000000000001'
\set otherUserID '3e820000-0000-0000-0000-000000000002'
\set proposalAcceptedID '3e820000-0000-0000-0000-000000000003'
\set proposalReadyID '3e820000-0000-0000-0000-000000000004'
\set proposalRejectedID '3e820000-0000-0000-0000-000000000005'
\set speakerUserID '3e820000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Invited co-speaker
select fx_user(:'coSpeakerUserID');

-- User who is not the invited co-speaker
select fx_user(:'otherUserID');

-- Proposal speaker
select fx_user(:'speakerUserID');

-- Pending proposal accepted by the co-speaker
insert into session_proposal (
    session_proposal_id,
    co_speaker_user_id,
    description,
    duration,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    user_id
) values (
    :'proposalAcceptedID',
    :'coSpeakerUserID',
    'Accepted proposal',
    make_interval(mins => 45),
    'beginner',
    'pending-co-speaker-response',
    'Accepted proposal',
    :'speakerUserID'
);

-- Proposal no longer awaiting the co-speaker
insert into session_proposal (
    session_proposal_id,
    co_speaker_user_id,
    description,
    duration,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    user_id
) values (
    :'proposalReadyID',
    :'coSpeakerUserID',
    'Ready proposal',
    make_interval(mins => 45),
    'beginner',
    'ready-for-submission',
    'Ready proposal',
    :'speakerUserID'
);

-- Pending proposal rejected by the co-speaker
insert into session_proposal (
    session_proposal_id,
    co_speaker_user_id,
    description,
    duration,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    user_id
) values (
    :'proposalRejectedID',
    :'coSpeakerUserID',
    'Rejected proposal',
    make_interval(mins => 45),
    'beginner',
    'pending-co-speaker-response',
    'Rejected proposal',
    :'speakerUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should make an accepted proposal ready for submission
select lives_ok(
    format(
        'select respond_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid, true)',
        :'coSpeakerUserID',
        :'proposalAcceptedID'
    ),
    'Should make an accepted proposal ready for submission'
);
select is(
    (
        select session_proposal_status_id
        from session_proposal
        where session_proposal_id = :'proposalAcceptedID'::uuid
    ),
    'ready-for-submission',
    'Should set the accepted proposal status to ready for submission'
);
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                resource_type,
                resource_id
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'proposalAcceptedID'
    ),
    format(
        $$
            values (
                'session_proposal_co_speaker_invitation_accepted',
                %L::uuid,
                'session_proposal',
                %L::uuid
            )
        $$,
        :'coSpeakerUserID',
        :'proposalAcceptedID'
    ),
    'Should audit the accepted invitation'
);

-- Should mark a rejected proposal as declined by the co-speaker
select lives_ok(
    format(
        'select respond_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid, false)',
        :'coSpeakerUserID',
        :'proposalRejectedID'
    ),
    'Should mark a rejected proposal as declined by the co-speaker'
);
select is(
    (
        select session_proposal_status_id
        from session_proposal
        where session_proposal_id = :'proposalRejectedID'::uuid
    ),
    'declined-by-co-speaker',
    'Should set the rejected proposal status to declined by the co-speaker'
);
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                resource_type,
                resource_id
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'proposalRejectedID'
    ),
    format(
        $$
            values (
                'session_proposal_co_speaker_invitation_rejected',
                %L::uuid,
                'session_proposal',
                %L::uuid
            )
        $$,
        :'coSpeakerUserID',
        :'proposalRejectedID'
    ),
    'Should audit the rejected invitation'
);

-- Should reject responses from users who are not the invited co-speaker
select throws_ok(
    format(
        'select respond_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid, true)',
        :'otherUserID',
        :'proposalReadyID'
    ),
    'OCG01',
    'session proposal invitation not found',
    'Should reject responses from users who are not the invited co-speaker'
);

-- Should reject responses to proposals not awaiting a co-speaker response
select throws_ok(
    format(
        'select respond_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid, true)',
        :'coSpeakerUserID',
        :'proposalReadyID'
    ),
    'OCG01',
    'session proposal is not awaiting co-speaker response',
    'Should reject responses to proposals not awaiting a co-speaker response'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
