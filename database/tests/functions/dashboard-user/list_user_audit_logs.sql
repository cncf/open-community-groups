-- Tests the user dashboard audit log action allow-list, scope and filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '4a080000-0000-0000-0000-000000000001'
\set otherActorAuditID '4a080000-0000-0000-0000-000000000002'
\set otherActorID '4a080000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose audit log is listed
select fx_user(:'actorID', jsonb_build_object('username', 'alice-user-audit-logs'));

-- Other user whose audit rows must be excluded
select fx_user(:'otherActorID', jsonb_build_object('username', 'bob-user-audit-logs'));

-- Audit rows for every user dashboard action plus a hidden action
insert into audit_log (action, resource_id, resource_type, actor_user_id) values
    ('community_team_invitation_accepted', :'actorID', 'user', :'actorID'),
    ('community_team_invitation_rejected', :'actorID', 'user', :'actorID'),
    ('event_admission_offer_declined', :'actorID', 'user', :'actorID'),
    ('event_attendee_invitation_accepted', :'actorID', 'user', :'actorID'),
    ('event_attendee_invitation_rejected', :'actorID', 'user', :'actorID'),
    ('group_notifications_muted', :'actorID', 'user', :'actorID'),
    ('group_notifications_unmuted', :'actorID', 'user', :'actorID'),
    ('group_team_invitation_accepted', :'actorID', 'user', :'actorID'),
    ('group_team_invitation_rejected', :'actorID', 'user', :'actorID'),
    ('group_updated', :'actorID', 'user', :'actorID'),
    ('inbox_conversation_started', :'actorID', 'user', :'actorID'),
    ('inbox_message_sent', :'actorID', 'user', :'actorID'),
    ('session_proposal_added', :'actorID', 'user', :'actorID'),
    ('session_proposal_co_speaker_invitation_accepted', :'actorID', 'user', :'actorID'),
    ('session_proposal_co_speaker_invitation_rejected', :'actorID', 'user', :'actorID'),
    ('session_proposal_deleted', :'actorID', 'user', :'actorID'),
    ('session_proposal_updated', :'actorID', 'user', :'actorID'),
    ('submission_resubmitted', :'actorID', 'user', :'actorID'),
    ('submission_withdrawn', :'actorID', 'user', :'actorID'),
    ('user_details_updated', :'actorID', 'user', :'actorID'),
    ('user_notification_preferences_updated', :'actorID', 'user', :'actorID'),
    ('user_password_updated', :'actorID', 'user', :'actorID');

-- Audit row of a user dashboard action performed by the other user
insert into audit_log (audit_log_id, action, resource_id, resource_type, actor_user_id)
values (:'otherActorAuditID', 'user_details_updated', :'otherActorID', 'user', :'otherActorID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore the actor filter
select is(
    (
        list_user_audit_logs(
            :'actorID'::uuid,
            '{"actor": "no-such-actor", "limit": 100}'::jsonb
        )::jsonb->>'total'
    )::int,
    21,
    'Should ignore the actor filter'
);

-- Should list every user dashboard action and skip hidden actions
select is(
    (
        select jsonb_agg(log_item->>'action' order by log_item->>'action' collate "C")
        from jsonb_array_elements(
            list_user_audit_logs(:'actorID'::uuid, '{"limit": 100}'::jsonb)::jsonb->'logs'
        ) log_item
    ),
    '[
        "community_team_invitation_accepted",
        "community_team_invitation_rejected",
        "event_admission_offer_declined",
        "event_attendee_invitation_accepted",
        "event_attendee_invitation_rejected",
        "group_notifications_muted",
        "group_notifications_unmuted",
        "group_team_invitation_accepted",
        "group_team_invitation_rejected",
        "inbox_conversation_started",
        "inbox_message_sent",
        "session_proposal_added",
        "session_proposal_co_speaker_invitation_accepted",
        "session_proposal_co_speaker_invitation_rejected",
        "session_proposal_deleted",
        "session_proposal_updated",
        "submission_resubmitted",
        "submission_withdrawn",
        "user_details_updated",
        "user_notification_preferences_updated",
        "user_password_updated"
    ]'::jsonb,
    'Should list every user dashboard action and skip hidden actions'
);

-- Should list only audit rows of the selected user
select is(
    jsonb_path_query_array(
        list_user_audit_logs(:'otherActorID'::uuid, '{}'::jsonb)::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'otherActorAuditID'),
    'Should list only audit rows of the selected user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
