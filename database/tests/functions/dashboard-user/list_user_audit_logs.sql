-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '00000000-0000-0000-0000-000000000011'
\set otherActorID '00000000-0000-0000-0000-000000000012'
\set audit1ID '00000000-0000-0000-0000-000000000101'
\set audit2ID '00000000-0000-0000-0000-000000000102'
\set audit3ID '00000000-0000-0000-0000-000000000103'
\set audit4ID '00000000-0000-0000-0000-000000000104'
\set audit5ID '00000000-0000-0000-0000-000000000105'
\set sessionProposalID '00000000-0000-0000-0000-000000000021'
\set submissionID '00000000-0000-0000-0000-000000000031'
\set sessionProposalLevelID 'beginner'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, name, username)
values
    (:'actorID', gen_random_bytes(32), 'alice@example.com', true, 'Alice', 'alice'),
    (:'otherActorID', gen_random_bytes(32), 'bob@example.com', true, 'Bob', 'bob');

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
    :'sessionProposalID',
    '2024-04-01 10:00:00+00',
    'Session about Rust alliances',
    make_interval(mins => 45),
    :'sessionProposalLevelID',
    'Rust for Alliances',
    :'actorID'
);

-- Audit log rows
insert into audit_log (
    audit_log_id,
    action,
    actor_user_id,
    actor_username,
    created_at,
    details,
    resource_id,
    resource_type
) values
    (
        :'audit1ID',
        'session_proposal_added',
        :'actorID',
        'alice',
        '2024-04-01 11:00:00+00',
        '{}'::jsonb,
        :'sessionProposalID',
        'session_proposal'
    ),
    (
        :'audit2ID',
        'user_details_updated',
        :'actorID',
        'alice',
        '2024-04-02 11:00:00+00',
        '{}'::jsonb,
        :'actorID',
        'user'
    ),
    (
        :'audit4ID',
        'event_attendee_invitation_accepted',
        :'actorID',
        'alice',
        '2024-04-01 12:00:00+00',
        '{"event_id": "00000000-0000-0000-0000-000000000041"}',
        :'actorID',
        'user'
    ),
    (
        :'audit5ID',
        'event_attendee_invitation_rejected',
        :'actorID',
        'alice',
        '2024-04-01 13:00:00+00',
        '{"event_id": "00000000-0000-0000-0000-000000000042"}',
        :'actorID',
        'user'
    ),
    (
        :'audit3ID',
        'submission_withdrawn',
        :'otherActorID',
        'bob',
        '2024-04-03 11:00:00+00',
        '{"status": "withdrawn"}',
        :'submissionID',
        'cfs_submission'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only actor-owned user dashboard actions
select is(
    list_user_audit_logs(
        :'actorID'::uuid,
        '{"limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "user_details_updated",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000102",
                "created_at": 1712055600,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000011",
                "resource_name": "Alice",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_rejected",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000105",
                "created_at": 1711976400,
                "details": {"event_id": "00000000-0000-0000-0000-000000000042"},
                "resource_id": "00000000-0000-0000-0000-000000000011",
                "resource_name": "Alice",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_accepted",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000104",
                "created_at": 1711972800,
                "details": {"event_id": "00000000-0000-0000-0000-000000000041"},
                "resource_id": "00000000-0000-0000-0000-000000000011",
                "resource_name": "Alice",
                "resource_type": "user"
            },
            {
                "action": "session_proposal_added",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1711969200,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000021",
                "resource_name": "Rust for Alliances",
                "resource_type": "session_proposal"
            }
        ]'::jsonb,
        'total',
        4
    ),
    'Should return only actor-owned user dashboard actions'
);

-- Should filter user audit logs by action and date range
select is(
    list_user_audit_logs(
        :'actorID'::uuid,
        '{"action": "session_proposal_added", "date_from": "2024-04-01", "date_to": "2024-04-01", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "session_proposal_added",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1711969200,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000021",
                "resource_name": "Rust for Alliances",
                "resource_type": "session_proposal"
            }
        ]'::jsonb,
        'total',
        1
    ),
    'Should filter user audit logs by action and date range'
);

-- Should return user audit logs in ascending order with pagination
select is(
    list_user_audit_logs(
        :'actorID'::uuid,
        '{"limit": 1, "offset": 0, "sort": "created-asc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "session_proposal_added",
                "actor_username": "alice",
                "audit_log_id": "00000000-0000-0000-0000-000000000101",
                "created_at": 1711969200,
                "details": {},
                "resource_id": "00000000-0000-0000-0000-000000000021",
                "resource_name": "Rust for Alliances",
                "resource_type": "session_proposal"
            }
        ]'::jsonb,
        'total',
        4
    ),
    'Should return user audit logs in ascending order with pagination'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
