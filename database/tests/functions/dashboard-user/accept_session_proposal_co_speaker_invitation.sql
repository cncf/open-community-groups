-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set coSpeakerUserID '4a040000-0000-0000-0000-000000000001'
\set proposalPendingID '4a040000-0000-0000-0000-000000000002'
\set proposalReadyID '4a040000-0000-0000-0000-000000000003'
\set speakerUserID '4a040000-0000-0000-0000-000000000004'
\set userID2 '4a040000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'coSpeakerUserID',
    'hash-1',
    'co-speaker@example.com',
    true,
    'co-speaker'
), (
    :'speakerUserID',
    'hash-2',
    'speaker@example.com',
    true,
    'speaker'
), (
    :'userID2',
    'hash-3',
    'user2@example.com',
    true,
    'user2'
);

-- Session proposals
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
    :'proposalPendingID',
    :'coSpeakerUserID',
    'Pending proposal',
    make_interval(mins => 45),
    'beginner',
    'pending-co-speaker-response',
    'Pending proposal',
    :'speakerUserID'
), (
    :'proposalReadyID',
    :'coSpeakerUserID',
    'Ready proposal',
    make_interval(mins => 45),
    'beginner',
    'ready-for-submission',
    'Ready proposal',
    :'speakerUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should execute acceptance for pending invitation
select lives_ok(
    format(
        'select accept_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid)',
        :'coSpeakerUserID',
        :'proposalPendingID'
    ),
    'Should execute acceptance for pending invitation'
);

-- Should set proposal status to ready for submission after acceptance
select is(
    (
        select session_proposal_status_id
        from session_proposal
        where session_proposal_id = :'proposalPendingID'::uuid
    ),
    'ready-for-submission',
    'Should set proposal status to ready for submission after acceptance'
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
                'session_proposal_co_speaker_invitation_accepted',
                %L::uuid,
                'co-speaker',
                'session_proposal',
                %L::uuid
            )
        $$,
        :'coSpeakerUserID',
        :'proposalPendingID'
    ),
    'Should create the expected audit row'
);

-- Should reject acceptance when invitation is not pending
select throws_ok(
    format(
        'select accept_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid)',
        :'coSpeakerUserID',
        :'proposalReadyID'
    ),
    'session proposal is not awaiting co-speaker response',
    'Should reject acceptance when invitation is not pending'
);

-- Should reject acceptance for users that are not the invited co-speaker
select throws_ok(
    format(
        'select accept_session_proposal_co_speaker_invitation(%L::uuid, %L::uuid)',
        :'userID2',
        :'proposalReadyID'
    ),
    'session proposal invitation not found',
    'Should reject acceptance for users that are not the invited co-speaker'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
