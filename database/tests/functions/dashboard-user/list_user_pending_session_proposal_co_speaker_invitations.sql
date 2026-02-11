-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set coSpeakerID '00000000-0000-0000-0000-000000000071'
\set proposalOtherID '00000000-0000-0000-0000-000000000064'
\set proposalPending1ID '00000000-0000-0000-0000-000000000061'
\set proposalPending2ID '00000000-0000-0000-0000-000000000062'
\set proposalReadyID '00000000-0000-0000-0000-000000000063'
\set speakerID '00000000-0000-0000-0000-000000000070'
\set userEmptyID '00000000-0000-0000-0000-000000000099'
\set userOtherID '00000000-0000-0000-0000-000000000072'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name, photo_url) values
    (:'coSpeakerID', gen_random_bytes(32), 'co-speaker@example.com', 'co-speaker', true, 'Co Speaker', null),
    (
        :'speakerID',
        gen_random_bytes(32),
        'speaker@example.com',
        'speaker',
        true,
        'Speaker',
        'https://example.test/speaker.png'
    ),
    (:'userOtherID', gen_random_bytes(32), 'other@example.com', 'other-user', true, 'Other User', null);

-- Session proposals
insert into session_proposal (
    session_proposal_id,
    co_speaker_user_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    session_proposal_status_id,
    title,
    updated_at,
    user_id
) values
    (
        :'proposalPending1ID',
        :'coSpeakerID',
        '2024-01-02 00:00:00+00',
        'Pending invitation one',
        make_interval(mins => 30),
        'beginner',
        'pending-co-speaker-response',
        'Rust for Beginners',
        null,
        :'speakerID'
    ),
    (
        :'proposalPending2ID',
        :'coSpeakerID',
        '2024-01-01 00:00:00+00',
        'Pending invitation two',
        make_interval(mins => 45),
        'intermediate',
        'pending-co-speaker-response',
        'Advanced Rust',
        '2024-01-05 00:00:00+00',
        :'speakerID'
    ),
    (
        :'proposalReadyID',
        :'coSpeakerID',
        '2024-01-03 00:00:00+00',
        'Already accepted invitation',
        make_interval(mins => 30),
        'advanced',
        'ready-for-submission',
        'Rust Accepted',
        null,
        :'speakerID'
    ),
    (
        :'proposalOtherID',
        :'userOtherID',
        '2024-01-04 00:00:00+00',
        'Invitation for another user',
        make_interval(mins => 30),
        'advanced',
        'pending-co-speaker-response',
        'Rust Other User',
        null,
        :'speakerID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list pending co-speaker invitations ordered by latest update
select is(
    list_user_pending_session_proposal_co_speaker_invitations(:'coSpeakerID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'co_speaker', jsonb_build_object(
                'name', 'Co Speaker',
                'user_id', :'coSpeakerID'::uuid,
                'username', 'co-speaker'
            ),
            'created_at', (
                select extract(epoch from created_at)::bigint
                from session_proposal
                where session_proposal_id = :'proposalPending2ID'::uuid
            ),
            'description', 'Pending invitation two',
            'duration_minutes', 45,
            'has_submissions', false,
            'linked_session_id', null,
            'session_proposal_id', :'proposalPending2ID'::uuid,
            'session_proposal_level_id', 'intermediate',
            'session_proposal_level_name', (
                select display_name
                from session_proposal_level
                where session_proposal_level_id = 'intermediate'
            ),
            'session_proposal_status_id', 'pending-co-speaker-response',
            'speaker_name', 'Speaker',
            'speaker_photo_url', 'https://example.test/speaker.png',
            'status_name', (
                select display_name
                from session_proposal_status
                where session_proposal_status_id = 'pending-co-speaker-response'
            ),
            'title', 'Advanced Rust',
            'updated_at', (
                select extract(epoch from updated_at)::bigint
                from session_proposal
                where session_proposal_id = :'proposalPending2ID'::uuid
            )
        ),
        jsonb_build_object(
            'co_speaker', jsonb_build_object(
                'name', 'Co Speaker',
                'user_id', :'coSpeakerID'::uuid,
                'username', 'co-speaker'
            ),
            'created_at', (
                select extract(epoch from created_at)::bigint
                from session_proposal
                where session_proposal_id = :'proposalPending1ID'::uuid
            ),
            'description', 'Pending invitation one',
            'duration_minutes', 30,
            'has_submissions', false,
            'linked_session_id', null,
            'session_proposal_id', :'proposalPending1ID'::uuid,
            'session_proposal_level_id', 'beginner',
            'session_proposal_level_name', (
                select display_name
                from session_proposal_level
                where session_proposal_level_id = 'beginner'
            ),
            'session_proposal_status_id', 'pending-co-speaker-response',
            'speaker_name', 'Speaker',
            'speaker_photo_url', 'https://example.test/speaker.png',
            'status_name', (
                select display_name
                from session_proposal_status
                where session_proposal_status_id = 'pending-co-speaker-response'
            ),
            'title', 'Rust for Beginners',
            'updated_at', null
        )
    ),
    'Should list pending co-speaker invitations ordered by latest update'
);

-- Should return empty when there are no pending invitations
select is(
    list_user_pending_session_proposal_co_speaker_invitations(:'userEmptyID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty when there are no pending invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
