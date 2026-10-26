-- Tests group-scoped audit log actions and filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actor1ID '3a1f0000-0000-0000-0000-000000000011'
\set actor2ID '3a1f0000-0000-0000-0000-000000000012'
\set audit1ID '3a1f0000-0000-0000-0000-000000000101'
\set audit2ID '3a1f0000-0000-0000-0000-000000000102'
\set audit3ID '3a1f0000-0000-0000-0000-000000000103'
\set audit4ID '3a1f0000-0000-0000-0000-000000000104'
\set audit5ID '3a1f0000-0000-0000-0000-000000000106'
\set audit6ID '3a1f0000-0000-0000-0000-000000000107'
\set audit7ID '3a1f0000-0000-0000-0000-000000000108'
\set audit8ID '3a1f0000-0000-0000-0000-000000000109'
\set audit9ID '3a1f0000-0000-0000-0000-000000000110'
\set audit10ID '3a1f0000-0000-0000-0000-000000000111'
\set audit11ID '3a1f0000-0000-0000-0000-000000000112'
\set audit12ID '3a1f0000-0000-0000-0000-000000000113'
\set audit13ID '3a1f0000-0000-0000-0000-000000000114'
\set audit14ID '3a1f0000-0000-0000-0000-000000000115'
\set audit15ID '3a1f0000-0000-0000-0000-000000000116'
\set audit16ID '3a1f0000-0000-0000-0000-000000000117'
\set cohostGroupID '3a1f0000-0000-0000-0000-000000000033'
\set communityID '3a1f0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a1f0000-0000-0000-0000-000000000022'
\set eventID '3a1f0000-0000-0000-0000-000000000051'
\set eventSurveyAddedAuditID '3a1f0000-0000-0000-0000-000000000121'
\set eventSurveyClosedAuditID '3a1f0000-0000-0000-0000-000000000122'
\set eventSurveyDeletedAuditID '3a1f0000-0000-0000-0000-000000000123'
\set eventSurveyDeletedID '3a1f0000-0000-0000-0000-000000000072'
\set eventSurveyID '3a1f0000-0000-0000-0000-000000000071'
\set eventSurveyMarkedReadyAuditID '3a1f0000-0000-0000-0000-000000000124'
\set eventSurveyMovedToDraftAuditID '3a1f0000-0000-0000-0000-000000000125'
\set eventSurveyReopenedAuditID '3a1f0000-0000-0000-0000-000000000126'
\set eventSurveyUpdatedAuditID '3a1f0000-0000-0000-0000-000000000127'
\set groupCategoryID '3a1f0000-0000-0000-0000-000000000021'
\set groupID '3a1f0000-0000-0000-0000-000000000031'
\set inboxAuditID '3a1f0000-0000-0000-0000-000000000118'
\set inboxConversationID '3a1f0000-0000-0000-0000-000000000061'
\set inboxSpamMarkedAuditID '3a1f0000-0000-0000-0000-000000000119'
\set inboxSpamUnmarkedAuditID '3a1f0000-0000-0000-0000-000000000120'
\set otherGroupID '3a1f0000-0000-0000-0000-000000000032'
\set targetUserID '3a1f0000-0000-0000-0000-000000000041'
\set wildcardActorID '3a1f0000-0000-0000-0000-000000000013'
\set wildcardAuditID '3a1f0000-0000-0000-0000-000000000105'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
select fx_user(:'actor1ID', jsonb_build_object('username', 'alice-list-group-audit-logs'));
select fx_user(:'actor2ID', jsonb_build_object('username', 'bob-list-group-audit-logs'));
select fx_user(:'wildcardActorID', jsonb_build_object('username', 'userx1-list-group-audit-logs'));
select fx_user(:'targetUserID', jsonb_build_object(
    'name', 'Sara',
    'username', 'sara'
));

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Group whose audit log holds only event co-host actions
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');

-- Groups
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Platform'));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('name', 'Recovery Event'));

-- Inbox conversation answered by the group
insert into inbox_conversation (inbox_conversation_id, group_id, inbox_conversation_status_id, user_id)
values (:'inboxConversationID', :'groupID', 'answered', :'targetUserID');

-- Survey whose audit rows resolve its title
insert into event_survey (event_survey_id, event_id, title)
values (:'eventSurveyID', :'eventID', 'Feedback Survey');

-- Audit log rows
insert into audit_log (
    audit_log_id,
    action,
    actor_user_id,
    actor_username,
    community_id,
    created_at,
    details,
    group_id,
    resource_id,
    resource_type
) values
    (
        :'audit1ID',
        'group_updated',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-01 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'groupID',
        'group'
    ),
    (
        :'audit2ID',
        'group_team_member_added',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-03-02 10:00:00+00',
        '{"role": "admin"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit5ID',
        'event_invitation_request_accepted',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-03-02 11:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000051"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit6ID',
        'event_invitation_request_rejected',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-02 12:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000052"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit7ID',
        'event_attendee_invitation_accepted',
        :'targetUserID',
        'sara',
        :'communityID',
        '2024-03-02 13:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000053"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit8ID',
        'event_attendee_invitation_rejected',
        :'targetUserID',
        'sara',
        :'communityID',
        '2024-03-02 14:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000054"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit9ID',
        'event_attendee_invitation_sent',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-03-02 15:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000055"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit10ID',
        'event_attendee_invitation_canceled',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-02 16:00:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000056"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit11ID',
        'event_attendee_attendance_canceled',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-02 16:30:00+00',
        '{"event_id": "3a1f0000-0000-0000-0000-000000000057"}',
        :'groupID',
        :'targetUserID',
        'user'
    ),
    (
        :'audit3ID',
        'event_added',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-03 10:00:00+00',
        '{}'::jsonb,
        :'otherGroupID',
        :'otherGroupID',
        'event'
    ),
    (
        :'audit4ID',
        'community_updated',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-04 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'communityID',
        'community'
    ),
    (
        :'audit15ID',
        'event_purchase_external_payment_completed',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-03-03 11:00:00+00',
        '{"event_purchase_id": "3a1f0000-0000-0000-0000-000000000061", "user_id": "3a1f0000-0000-0000-0000-000000000041"}',
        :'groupID',
        :'eventID',
        'event'
    ),
    (
        :'audit16ID',
        'group_external_payments_updated',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-04 11:00:00+00',
        '{"external_payments_enabled": true}',
        :'groupID',
        :'groupID',
        'group'
    ),
    (
        :'audit12ID',
        'event_refund_recovery_completed',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-06 10:00:00+00',
        '{"recovery_reference": "bank-transfer-123"}',
        :'groupID',
        :'eventID',
        'event'
    ),
    (
        :'audit13ID',
        'event_application_fee_adjustment_recovery_completed',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-03-07 10:00:00+00',
        '{"recovery_reference": "fee-case-123"}',
        :'groupID',
        :'eventID',
        'event'
    ),
    (
        :'audit14ID',
        'event_credit_note_recovery_completed',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-03-08 10:00:00+00',
        '{"recovery_reference": "credit-case-456"}',
        :'groupID',
        :'eventID',
        'event'
    ),
    (
        :'inboxAuditID',
        'inbox_reply_sent',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-02-15 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'inboxConversationID',
        'inbox_conversation'
    ),
    (
        :'inboxSpamMarkedAuditID',
        'inbox_conversation_marked_as_spam',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-02-14 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'inboxConversationID',
        'inbox_conversation'
    ),
    (
        :'inboxSpamUnmarkedAuditID',
        'inbox_conversation_unmarked_as_spam',
        :'actor2ID',
        'bob-list-group-audit-logs',
        :'communityID',
        '2024-02-13 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'inboxConversationID',
        'inbox_conversation'
    ),
    (
        :'wildcardAuditID',
        'group_updated',
        :'wildcardActorID',
        'userx1-list-group-audit-logs',
        :'communityID',
        '2024-03-05 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'groupID',
        'group'
    ),
    (
        :'eventSurveyAddedAuditID',
        'event_survey_added',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-01 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'eventSurveyID',
        'event_survey'
    ),
    (
        :'eventSurveyUpdatedAuditID',
        'event_survey_updated',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-02 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'eventSurveyID',
        'event_survey'
    ),
    (
        :'eventSurveyMarkedReadyAuditID',
        'event_survey_marked_ready',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-03 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'eventSurveyID',
        'event_survey'
    ),
    (
        :'eventSurveyClosedAuditID',
        'event_survey_closed',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-04 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'eventSurveyID',
        'event_survey'
    ),
    (
        :'eventSurveyReopenedAuditID',
        'event_survey_reopened',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-05 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'eventSurveyID',
        'event_survey'
    ),
    (
        :'eventSurveyMovedToDraftAuditID',
        'event_survey_moved_to_draft',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-06 10:00:00+00',
        '{}'::jsonb,
        :'groupID',
        :'eventSurveyID',
        'event_survey'
    ),
    (
        :'eventSurveyDeletedAuditID',
        'event_survey_deleted',
        :'actor1ID',
        'alice-list-group-audit-logs',
        :'communityID',
        '2024-01-07 10:00:00+00',
        '{"responses_count": 2, "title": "Old Survey"}',
        :'groupID',
        :'eventSurveyDeletedID',
        'event_survey'
    );

-- Audit rows for every event co-host action
insert into audit_log (action, community_id, group_id, resource_id, resource_type) values
    ('event_cohost_approved', :'communityID', :'cohostGroupID', :'eventID', 'event'),
    ('event_cohost_canceled', :'communityID', :'cohostGroupID', :'eventID', 'event'),
    ('event_cohost_closed', :'communityID', :'cohostGroupID', :'eventID', 'event'),
    ('event_cohost_invited', :'communityID', :'cohostGroupID', :'eventID', 'event'),
    ('event_cohost_rejected', :'communityID', :'cohostGroupID', :'eventID', 'event'),
    ('event_cohost_removed', :'communityID', :'cohostGroupID', :'eventID', 'event');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only group dashboard actions for the selected group
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "event_credit_note_recovery_completed",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000115",
                "created_at": 1709892000,
                "details": {"recovery_reference": "credit-case-456"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000051",
                "resource_name": "Recovery Event",
                "resource_type": "event"
            },
            {
                "action": "event_application_fee_adjustment_recovery_completed",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000114",
                "created_at": 1709805600,
                "details": {"recovery_reference": "fee-case-123"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000051",
                "resource_name": "Recovery Event",
                "resource_type": "event"
            },
            {
                "action": "event_refund_recovery_completed",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000113",
                "created_at": 1709719200,
                "details": {"recovery_reference": "bank-transfer-123"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000051",
                "resource_name": "Recovery Event",
                "resource_type": "event"
            },
            {
                "action": "group_updated",
                "actor_username": "userx1-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000105",
                "created_at": 1709632800,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            },
            {
                "action": "group_external_payments_updated",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000117",
                "created_at": 1709550000,
                "details": {"external_payments_enabled": true},
                "resource_id": "3a1f0000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            },
            {
                "action": "event_purchase_external_payment_completed",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000116",
                "created_at": 1709463600,
                "details": {"event_purchase_id": "3a1f0000-0000-0000-0000-000000000061", "user_id": "3a1f0000-0000-0000-0000-000000000041"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000051",
                "resource_name": "Recovery Event",
                "resource_type": "event"
            },
            {
                "action": "event_attendee_attendance_canceled",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000112",
                "created_at": 1709397000,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000057"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_canceled",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000111",
                "created_at": 1709395200,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000056"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_sent",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000110",
                "created_at": 1709391600,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000055"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_rejected",
                "actor_username": "sara",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000109",
                "created_at": 1709388000,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000054"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_attendee_invitation_accepted",
                "actor_username": "sara",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000108",
                "created_at": 1709384400,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000053"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_invitation_request_rejected",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000107",
                "created_at": 1709380800,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000052"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "event_invitation_request_accepted",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000106",
                "created_at": 1709377200,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000051"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "group_team_member_added",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            },
            {
                "action": "group_updated",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000101",
                "created_at": 1709287200,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000031",
                "resource_name": "Platform",
                "resource_type": "group"
            },
            {
                "action": "inbox_reply_sent",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000118",
                "created_at": 1707991200,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000061",
                "resource_name": "Platform",
                "resource_type": "inbox_conversation"
            },
            {
                "action": "inbox_conversation_marked_as_spam",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000119",
                "created_at": 1707904800,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000061",
                "resource_name": "Platform",
                "resource_type": "inbox_conversation"
            },
            {
                "action": "inbox_conversation_unmarked_as_spam",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000120",
                "created_at": 1707818400,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000061",
                "resource_name": "Platform",
                "resource_type": "inbox_conversation"
            },
            {
                "action": "event_survey_deleted",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000123",
                "created_at": 1704621600,
                "details": {"responses_count": 2, "title": "Old Survey"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000072",
                "resource_name": null,
                "resource_type": "event_survey"
            },
            {
                "action": "event_survey_moved_to_draft",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000125",
                "created_at": 1704535200,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000071",
                "resource_name": "Feedback Survey",
                "resource_type": "event_survey"
            },
            {
                "action": "event_survey_reopened",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000126",
                "created_at": 1704448800,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000071",
                "resource_name": "Feedback Survey",
                "resource_type": "event_survey"
            },
            {
                "action": "event_survey_closed",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000122",
                "created_at": 1704362400,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000071",
                "resource_name": "Feedback Survey",
                "resource_type": "event_survey"
            },
            {
                "action": "event_survey_marked_ready",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000124",
                "created_at": 1704276000,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000071",
                "resource_name": "Feedback Survey",
                "resource_type": "event_survey"
            },
            {
                "action": "event_survey_updated",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000127",
                "created_at": 1704189600,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000071",
                "resource_name": "Feedback Survey",
                "resource_type": "event_survey"
            },
            {
                "action": "event_survey_added",
                "actor_username": "alice-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000121",
                "created_at": 1704103200,
                "details": {},
                "resource_id": "3a1f0000-0000-0000-0000-000000000071",
                "resource_name": "Feedback Survey",
                "resource_type": "event_survey"
            }
        ]'::jsonb,
        'total',
        25
    ),
    'Should return only group dashboard actions for the selected group'
);

-- Should include every event co-host audit action
select is(
    (
        select jsonb_agg(log_item->>'action' order by log_item->>'action')
        from jsonb_array_elements(
            list_group_audit_logs(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb->'logs'
        ) log_item
    ),
    '["event_cohost_approved","event_cohost_canceled","event_cohost_closed","event_cohost_invited","event_cohost_rejected","event_cohost_removed"]'::jsonb,
    'Should include every event co-host audit action'
);

-- Should filter group audit logs by actor and action
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"action": "event_invitation_request_accepted", "actor": "bo", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "event_invitation_request_accepted",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000106",
                "created_at": 1709377200,
                "details": {"event_id": "3a1f0000-0000-0000-0000-000000000051"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        1
    ),
    'Should filter group audit logs by actor and action'
);

-- Should return group audit logs in ascending order with pagination
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"date_from": "2024-03-01", "date_to": "2024-03-02", "limit": 1, "offset": 1, "sort": "created-asc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[
            {
                "action": "group_team_member_added",
                "actor_username": "bob-list-group-audit-logs",
                "audit_log_id": "3a1f0000-0000-0000-0000-000000000102",
                "created_at": 1709373600,
                "details": {"role": "admin"},
                "resource_id": "3a1f0000-0000-0000-0000-000000000041",
                "resource_name": "Sara",
                "resource_type": "user"
            }
        ]'::jsonb,
        'total',
        9
    ),
    'Should return group audit logs in ascending order with pagination'
);

-- Should treat actor filter metacharacters as literal text
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"actor": "user_1", "limit": 50, "offset": 0, "sort": "created-desc"}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'logs',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should treat actor filter metacharacters as literal text'
);

-- Should default unsupported sort values to created descending
select is(
    list_group_audit_logs(
        :'groupID'::uuid,
        '{"limit": 1, "offset": 0, "sort": "resource-asc"}'::jsonb
    )::jsonb#>>'{logs,0,action}',
    'event_credit_note_recovery_completed',
    'Should default unsupported group audit sort values to created descending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
