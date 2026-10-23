-- Tests the group dashboard audit log action allow-list and scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a1f0000-0000-0000-0000-000000000001'
\set groupCategoryID '3a1f0000-0000-0000-0000-000000000021'
\set groupID '3a1f0000-0000-0000-0000-000000000031'
\set otherGroupAuditID '3a1f0000-0000-0000-0000-000000000101'
\set otherGroupID '3a1f0000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community of the audited groups
select fx_community(:'communityID');

-- Group category of the audited groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group whose audit log is listed
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Other group whose audit rows must be excluded
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Audit rows for every group dashboard action plus hidden actions
insert into audit_log (action, resource_id, resource_type, community_id, group_id) values
    ('admission_offer_canceled', :'groupID', 'group', :'communityID', :'groupID'),
    ('admission_offer_expired', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_added', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_artwork_added', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_artwork_deleted', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_awarded', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_deleted', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_revoked', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_revoked_account_deleted', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_revoked_by_recipient', :'groupID', 'group', :'communityID', :'groupID'),
    ('badge_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('cfs_submission_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_added', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_admission_offer_canceled', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_admission_offer_declined', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_admission_offer_reissued', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_application_fee_adjustment_recovery_completed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_attendee_attendance_canceled', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_attendee_checked_in', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_attendee_invitation_accepted', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_attendee_invitation_canceled', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_attendee_invitation_rejected', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_attendee_invitation_sent', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_canceled', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_cohost_approved', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_cohost_canceled', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_cohost_closed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_cohost_invited', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_cohost_rejected', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_cohost_removed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_credit_note_recovery_completed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_custom_notification_sent', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_deleted', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_invitation_request_accepted', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_invitation_request_rejected', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_published', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_purchase_external_payment_completed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_refund_approved', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_refund_recovery_completed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_refund_rejected', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_refund_requested', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_refunded', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_registration_questions_answered', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_added', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_closed', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_deleted', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_marked_ready', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_moved_to_draft', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_reopened', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_survey_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_ticket_waitlist_offer_created', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_unpublished', :'groupID', 'group', :'communityID', :'groupID'),
    ('event_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_custom_notification_sent', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_external_payments_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_payment_recipient_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_sponsor_added', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_sponsor_deleted', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_sponsor_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_team_member_added', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_team_member_removed', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_team_member_role_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('group_updated', :'groupID', 'group', :'communityID', :'groupID'),
    ('inbox_conversation_closed', :'groupID', 'group', :'communityID', :'groupID'),
    ('inbox_conversation_marked_as_spam', :'groupID', 'group', :'communityID', :'groupID'),
    ('inbox_conversation_reopened', :'groupID', 'group', :'communityID', :'groupID'),
    ('inbox_conversation_unmarked_as_spam', :'groupID', 'group', :'communityID', :'groupID'),
    ('inbox_reply_sent', :'groupID', 'group', :'communityID', :'groupID');

-- Audit row of a group dashboard action in the other group
insert into audit_log (audit_log_id, action, resource_id, resource_type, community_id, group_id)
values (:'otherGroupAuditID', 'group_updated', :'otherGroupID', 'group', :'communityID', :'otherGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list every group dashboard action and skip hidden actions
select is(
    (
        select jsonb_agg(log_item->>'action' order by log_item->>'action' collate "C")
        from jsonb_array_elements(
            list_group_audit_logs(:'groupID'::uuid, '{"limit": 100}'::jsonb)::jsonb->'logs'
        ) log_item
    ),
    '[
        "admission_offer_expired",
        "badge_added",
        "badge_artwork_added",
        "badge_artwork_deleted",
        "badge_awarded",
        "badge_deleted",
        "badge_revoked",
        "badge_revoked_account_deleted",
        "badge_revoked_by_recipient",
        "badge_updated",
        "cfs_submission_updated",
        "event_added",
        "event_admission_offer_canceled",
        "event_admission_offer_declined",
        "event_admission_offer_reissued",
        "event_application_fee_adjustment_recovery_completed",
        "event_attendee_attendance_canceled",
        "event_attendee_checked_in",
        "event_attendee_invitation_accepted",
        "event_attendee_invitation_canceled",
        "event_attendee_invitation_rejected",
        "event_attendee_invitation_sent",
        "event_canceled",
        "event_cohost_approved",
        "event_cohost_canceled",
        "event_cohost_closed",
        "event_cohost_invited",
        "event_cohost_rejected",
        "event_cohost_removed",
        "event_credit_note_recovery_completed",
        "event_custom_notification_sent",
        "event_deleted",
        "event_invitation_request_accepted",
        "event_invitation_request_rejected",
        "event_published",
        "event_purchase_external_payment_completed",
        "event_refund_approved",
        "event_refund_recovery_completed",
        "event_refund_rejected",
        "event_refund_requested",
        "event_refunded",
        "event_survey_added",
        "event_survey_closed",
        "event_survey_deleted",
        "event_survey_marked_ready",
        "event_survey_moved_to_draft",
        "event_survey_reopened",
        "event_survey_updated",
        "event_ticket_waitlist_offer_created",
        "event_unpublished",
        "event_updated",
        "group_custom_notification_sent",
        "group_external_payments_updated",
        "group_payment_recipient_updated",
        "group_sponsor_added",
        "group_sponsor_deleted",
        "group_sponsor_updated",
        "group_team_member_added",
        "group_team_member_removed",
        "group_team_member_role_updated",
        "group_updated",
        "inbox_conversation_closed",
        "inbox_conversation_marked_as_spam",
        "inbox_conversation_reopened",
        "inbox_conversation_unmarked_as_spam",
        "inbox_reply_sent"
    ]'::jsonb,
    'Should list every group dashboard action and skip hidden actions'
);

-- Should list only audit rows of the selected group
select is(
    jsonb_path_query_array(
        list_group_audit_logs(:'otherGroupID'::uuid, '{}'::jsonb)::jsonb,
        '$.logs[*].audit_log_id'
    ),
    jsonb_build_array(:'otherGroupAuditID'),
    'Should list only audit rows of the selected group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
