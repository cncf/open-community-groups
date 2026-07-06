-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '4a080000-0000-0000-0000-000000000001'
\set audit1ID '4a080000-0000-0000-0000-000000000002'
\set audit2ID '4a080000-0000-0000-0000-000000000003'
\set audit3ID '4a080000-0000-0000-0000-000000000004'
\set audit4ID '4a080000-0000-0000-0000-000000000005'
\set audit5ID '4a080000-0000-0000-0000-000000000006'
\set eventAcceptedID '4a080000-0000-0000-0000-000000000007'
\set eventRejectedID '4a080000-0000-0000-0000-000000000008'
\set otherActorID '4a080000-0000-0000-0000-000000000009'
\set sessionProposalID '4a080000-0000-0000-0000-000000000010'
\set sessionProposalLevelID 'beginner'
\set submissionID '4a080000-0000-0000-0000-000000000011'

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
    :'actorID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice'
), (
    :'otherActorID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    'Bob'
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
    :'sessionProposalID',
    '2024-04-01 10:00:00+00',
    'Session about Rust communities',
    make_interval(mins => 45),
    :'sessionProposalLevelID',
    'Rust for Communities',
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
        jsonb_build_object('event_id', :'eventAcceptedID'),
        :'actorID',
        'user'
    ),
    (
        :'audit5ID',
        'event_attendee_invitation_rejected',
        :'actorID',
        'alice',
        '2024-04-01 13:00:00+00',
        jsonb_build_object('event_id', :'eventRejectedID'),
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
        format(
            $json$
                [
                    {
                        "action": "user_details_updated",
                        "actor_username": "alice",
                        "audit_log_id": "%s",
                        "created_at": 1712055600,
                        "details": {},
                        "resource_id": "%s",
                        "resource_name": "Alice",
                        "resource_type": "user"
                    },
                    {
                        "action": "event_attendee_invitation_rejected",
                        "actor_username": "alice",
                        "audit_log_id": "%s",
                        "created_at": 1711976400,
                        "details": {"event_id": "%s"},
                        "resource_id": "%s",
                        "resource_name": "Alice",
                        "resource_type": "user"
                    },
                    {
                        "action": "event_attendee_invitation_accepted",
                        "actor_username": "alice",
                        "audit_log_id": "%s",
                        "created_at": 1711972800,
                        "details": {"event_id": "%s"},
                        "resource_id": "%s",
                        "resource_name": "Alice",
                        "resource_type": "user"
                    },
                    {
                        "action": "session_proposal_added",
                        "actor_username": "alice",
                        "audit_log_id": "%s",
                        "created_at": 1711969200,
                        "details": {},
                        "resource_id": "%s",
                        "resource_name": "Rust for Communities",
                        "resource_type": "session_proposal"
                    }
                ]
            $json$,
            :'audit2ID',
            :'actorID',
            :'audit5ID',
            :'eventRejectedID',
            :'actorID',
            :'audit4ID',
            :'eventAcceptedID',
            :'actorID',
            :'audit1ID',
            :'sessionProposalID'
        )::jsonb,
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
        format(
            $json$
                [
                    {
                        "action": "session_proposal_added",
                        "actor_username": "alice",
                        "audit_log_id": "%s",
                        "created_at": 1711969200,
                        "details": {},
                        "resource_id": "%s",
                        "resource_name": "Rust for Communities",
                        "resource_type": "session_proposal"
                    }
                ]
            $json$,
            :'audit1ID',
            :'sessionProposalID'
        )::jsonb,
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
        format(
            $json$
                [
                    {
                        "action": "session_proposal_added",
                        "actor_username": "alice",
                        "audit_log_id": "%s",
                        "created_at": 1711969200,
                        "details": {},
                        "resource_id": "%s",
                        "resource_name": "Rust for Communities",
                        "resource_type": "session_proposal"
                    }
                ]
            $json$,
            :'audit1ID',
            :'sessionProposalID'
        )::jsonb,
        'total',
        4
    ),
    'Should return user audit logs in ascending order with pagination'
);

-- Should default unsupported sort values to created descending
select is(
    list_user_audit_logs(
        :'actorID'::uuid,
        '{"limit": 1, "offset": 0, "sort": "resource-asc"}'::jsonb
    )::jsonb#>>'{logs,0,action}',
    'user_details_updated',
    'Should default unsupported user audit sort values to created descending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
