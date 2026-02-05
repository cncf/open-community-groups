-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set proposal1ID '00000000-0000-0000-0000-000000000061'
\set proposal2ID '00000000-0000-0000-0000-000000000062'
\set userID '00000000-0000-0000-0000-000000000071'
\set userEmptyID '00000000-0000-0000-0000-000000000099'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice');

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values
    (
        :'proposal1ID',
        '2024-01-02 00:00:00+00',
        'Session about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust 101',
        :'userID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Session about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go 101',
        :'userID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list session proposals with pagination
select is(
    list_user_session_proposals(:'userID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'session_proposals', jsonb_build_array(
            jsonb_build_object(
                'co_speaker', null,
                'created_at', (select extract(epoch from created_at)::bigint from session_proposal
                    where session_proposal_id = :'proposal2ID'::uuid),
                'description', 'Session about Go',
                'duration_minutes', 60,
                'has_submissions', false,
                'linked_session_id', null,
                'session_proposal_id', :'proposal2ID'::uuid,
                'session_proposal_level_id', 'intermediate',
                'session_proposal_level_name', 'Intermediate',
                'title', 'Go 101',
                'updated_at', null
            ),
            jsonb_build_object(
                'co_speaker', null,
                'created_at', (select extract(epoch from created_at)::bigint from session_proposal
                    where session_proposal_id = :'proposal1ID'::uuid),
                'description', 'Session about Rust',
                'duration_minutes', 45,
                'has_submissions', false,
                'linked_session_id', null,
                'session_proposal_id', :'proposal1ID'::uuid,
                'session_proposal_level_id', 'beginner',
                'session_proposal_level_name', 'Beginner',
                'title', 'Rust 101',
                'updated_at', null
            )
        ),
        'total', 2
    ),
    'Should list session proposals with pagination'
);

-- Should paginate proposals
select is(
    list_user_session_proposals(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'session_proposals', jsonb_build_array(
            jsonb_build_object(
                'co_speaker', null,
                'created_at', (select extract(epoch from created_at)::bigint from session_proposal
                    where session_proposal_id = :'proposal1ID'::uuid),
                'description', 'Session about Rust',
                'duration_minutes', 45,
                'has_submissions', false,
                'linked_session_id', null,
                'session_proposal_id', :'proposal1ID'::uuid,
                'session_proposal_level_id', 'beginner',
                'session_proposal_level_name', 'Beginner',
                'title', 'Rust 101',
                'updated_at', null
            )
        ),
        'total', 2
    ),
    'Should paginate proposals'
);

-- Should return empty proposals for users without proposals
select is(
    list_user_session_proposals(:'userEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'session_proposals', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty proposals for users without proposals'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
