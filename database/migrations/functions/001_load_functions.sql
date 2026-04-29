{{ template "auth/get_user_by_id.sql" }} -- Do not sort alphabetically, has dependency
{{ template "auth/get_user_by_email.sql" }}
{{ template "auth/get_user_by_id_verified.sql" }}
{{ template "auth/get_user_by_username.sql" }}
{{ template "auth/sign_up_user.sql" }}
{{ template "auth/update_user_details.sql" }}
{{ template "auth/update_user_password.sql" }}
{{ template "auth/update_user_provider.sql" }}
{{ template "auth/user_has_community_permission.sql" }}
{{ template "auth/user_has_group_permission.sql" }}
{{ template "auth/verify_email.sql" }}

{{ template "common/escape_ilike_pattern.sql" }}
{{ template "common/generate_slug.sql" }}
{{ template "common/generate_slug_from_source.sql" }}
{{ template "common/get_community_full.sql" }}
{{ template "common/get_community_summary.sql" }} -- Do not sort alphabetically, has dependency
{{ template "common/list_event_discount_codes.sql" }} -- Dependency for get_event_full and payments
{{ template "common/list_event_ticket_types.sql" }} -- Dependency for get_event_full and payments
{{ template "common/get_group_summary.sql" }} -- Do not sort alphabetically, has dependency
{{ template "common/get_event_full.sql" }}
{{ template "common/get_event_summary.sql" }}
{{ template "common/get_group_full.sql" }}
{{ template "common/insert_audit_log.sql" }}
{{ template "common/list_event_cfs_labels.sql" }}
{{ template "common/list_redirects.sql" }}
{{ template "common/search_events.sql" }}
{{ template "common/search_groups.sql" }}
{{ template "community/get_community_id_by_name.sql" }}
{{ template "community/get_community_name_by_id.sql" }}
{{ template "community/get_community_recently_added_groups.sql" }}
{{ template "community/get_community_site_stats.sql" }}
{{ template "community/get_community_upcoming_events.sql" }}
{{ template "community/update_community_views.sql" }}

{{ template "dashboard-common/search_user.sql" }}
{{ template "dashboard-common/update_group.sql" }}

{{ template "dashboard-community/activate_group.sql" }}
{{ template "dashboard-community/add_community_team_member.sql" }}
{{ template "dashboard-community/add_event_category.sql" }}
{{ template "dashboard-community/add_group.sql" }}
{{ template "dashboard-community/add_group_category.sql" }}
{{ template "dashboard-community/add_region.sql" }}
{{ template "dashboard-community/deactivate_group.sql" }}
{{ template "dashboard-community/delete_community_team_member.sql" }}
{{ template "dashboard-community/delete_event_category.sql" }}
{{ template "dashboard-community/delete_group.sql" }}
{{ template "dashboard-community/delete_group_category.sql" }}
{{ template "dashboard-community/delete_region.sql" }}
{{ template "dashboard-community/get_community_stats.sql" }}
{{ template "dashboard-community/list_community_audit_logs.sql" }}
{{ template "dashboard-community/list_community_roles.sql" }}
{{ template "dashboard-community/list_community_team_members.sql" }}
{{ template "dashboard-community/list_group_categories.sql" }}
{{ template "dashboard-community/list_regions.sql" }}
{{ template "dashboard-community/list_user_communities.sql" }}
{{ template "dashboard-community/update_community.sql" }}
{{ template "dashboard-community/update_community_team_member_role.sql" }}
{{ template "dashboard-community/update_event_category.sql" }}
{{ template "dashboard-community/update_group_category.sql" }}
{{ template "dashboard-community/update_region.sql" }}

{{ template "dashboard-group/get_event_ticket_capacity.sql" }} -- Dependency for add/update_event
{{ template "dashboard-group/list_payment_currency_codes.sql" }} -- Dependency for payment currency validation and dashboard forms
{{ template "dashboard-group/validate_payment_currency_code.sql" }} -- Dependency for payment amount validation
{{ template "dashboard-group/validate_payment_amount.sql" }} -- Dependency for event ticketing and checkout validation
{{ template "dashboard-group/validate_event_capacity.sql" }} -- Dependency for add/update_event
{{ template "dashboard-group/validate_event_cfs_labels_payload.sql" }} -- Dependency for add/update_event
{{ template "dashboard-group/validate_event_discount_codes_payload.sql" }} -- Dependency for validate_event_ticketing_payload
{{ template "dashboard-group/validate_event_enrollment_payload.sql" }} -- Dependency for add/update_event
{{ template "dashboard-group/validate_event_series_action_event_ids.sql" }} -- Dependency for series actions
{{ template "dashboard-group/validate_event_ticket_types_payload.sql" }} -- Dependency for validate_event_ticketing_payload
{{ template "dashboard-group/validate_event_ticketing_payload.sql" }} -- Dependency for add/update_event
{{ template "event/promote_event_waitlist.sql" }} -- Dependency for update_event and leave_event
{{ template "dashboard-group/sync_event_discount_codes.sql" }} -- Dependency for add/update_event
{{ template "dashboard-group/sync_event_ticket_types.sql" }} -- Dependency for add/update_event
{{ template "dashboard-group/accept_event_invitation_request.sql" }}
{{ template "dashboard-group/add_event.sql" }}
{{ template "dashboard-group/add_event_series.sql" }}
{{ template "dashboard-group/add_group_sponsor.sql" }}
{{ template "dashboard-group/add_group_team_member.sql" }}
{{ template "dashboard-group/cancel_event.sql" }}
{{ template "dashboard-group/cancel_event_series_events.sql" }}
{{ template "dashboard-group/delete_event.sql" }}
{{ template "dashboard-group/delete_event_series_events.sql" }}
{{ template "dashboard-group/delete_group_sponsor.sql" }}
{{ template "dashboard-group/delete_group_team_member.sql" }}
{{ template "dashboard-group/get_cfs_submission_notification_data.sql" }}
{{ template "dashboard-group/get_event_summary_dashboard.sql" }} -- Dependency for list_group_events
{{ template "dashboard-group/get_group_sponsor.sql" }}
{{ template "dashboard-group/get_group_stats.sql" }}
{{ template "dashboard-group/is_event_meeting_in_sync.sql" }}
{{ template "dashboard-group/is_session_meeting_in_sync.sql" }}
{{ template "dashboard-group/list_cfs_submission_statuses_for_review.sql" }}
{{ template "dashboard-group/list_event_approved_cfs_submissions.sql" }}
{{ template "dashboard-group/list_event_attendees_ids.sql" }}
{{ template "dashboard-group/list_event_categories.sql" }}
{{ template "dashboard-group/list_event_cfs_submissions.sql" }}
{{ template "dashboard-group/list_event_kinds.sql" }}
{{ template "dashboard-group/list_event_series_event_ids.sql" }}
{{ template "dashboard-group/list_event_series_publishable_event_ids.sql" }}
{{ template "dashboard-group/list_event_waitlist_ids.sql" }}
{{ template "dashboard-group/list_group_audit_logs.sql" }}
{{ template "dashboard-group/list_group_events.sql" }}
{{ template "dashboard-group/list_group_members.sql" }}
{{ template "dashboard-group/list_group_members_ids.sql" }}
{{ template "dashboard-group/list_group_roles.sql" }}
{{ template "dashboard-group/list_group_sponsors.sql" }}
{{ template "dashboard-group/list_group_team_members.sql" }}
{{ template "dashboard-group/list_group_team_members_ids.sql" }}
{{ template "dashboard-group/list_session_kinds.sql" }}
{{ template "dashboard-group/list_user_groups.sql" }}
{{ template "dashboard-group/manual_check_in_event.sql" }}
{{ template "dashboard-group/publish_event.sql" }}
{{ template "dashboard-group/publish_event_series_events.sql" }}
{{ template "dashboard-group/reject_event_invitation_request.sql" }}
{{ template "dashboard-group/search_event_attendees.sql" }}
{{ template "dashboard-group/search_event_invitation_requests.sql" }}
{{ template "dashboard-group/search_event_waitlist.sql" }}
{{ template "dashboard-group/sync_event_cfs_labels.sql" }} -- Dependency for update_event
{{ template "dashboard-group/sync_event_sessions.sql" }} -- Dependency for update_event
{{ template "dashboard-group/unpublish_event.sql" }}
{{ template "dashboard-group/unpublish_event_series_events.sql" }}
{{ template "dashboard-group/update_cfs_submission.sql" }}
{{ template "dashboard-group/validate_update_event_dates.sql" }} -- Dependency for update_event
{{ template "dashboard-group/update_group_sponsor.sql" }}
{{ template "dashboard-group/update_group_sponsor_featured.sql" }}
{{ template "dashboard-group/update_group_team_member_role.sql" }}
{{ template "dashboard-group/update_event.sql" }}

{{ template "dashboard-user/accept_community_team_invitation.sql" }}
{{ template "dashboard-user/accept_group_team_invitation.sql" }}
{{ template "dashboard-user/accept_session_proposal_co_speaker_invitation.sql" }}
{{ template "dashboard-user/add_session_proposal.sql" }}
{{ template "dashboard-user/delete_session_proposal.sql" }}
{{ template "dashboard-user/list_session_proposal_levels.sql" }}
{{ template "dashboard-user/list_user_audit_logs.sql" }}
{{ template "dashboard-user/list_user_cfs_submissions.sql" }}
{{ template "dashboard-user/list_user_community_team_invitations.sql" }}
{{ template "dashboard-user/list_user_events.sql" }}
{{ template "dashboard-user/list_user_group_team_invitations.sql" }}
{{ template "dashboard-user/list_user_pending_session_proposal_co_speaker_invitations.sql" }}
{{ template "dashboard-user/list_user_session_proposals.sql" }}
{{ template "dashboard-user/reject_community_team_invitation.sql" }}
{{ template "dashboard-user/reject_group_team_invitation.sql" }}
{{ template "dashboard-user/reject_session_proposal_co_speaker_invitation.sql" }}
{{ template "dashboard-user/resubmit_cfs_submission.sql" }}
{{ template "dashboard-user/update_session_proposal.sql" }}
{{ template "dashboard-user/withdraw_cfs_submission.sql" }}

{{ template "event/add_cfs_submission.sql" }}
{{ template "event/attend_event.sql" }}
{{ template "event/check_in_event.sql" }}
{{ template "event/ensure_event_is_active.sql" }}
{{ template "event/get_event_attendance.sql" }}
{{ template "event/get_event_full_by_slug.sql" }}
{{ template "event/get_event_summary_by_id.sql" }}
{{ template "event/is_event_check_in_window_open.sql" }}
{{ template "payments/release_event_discount_code_availability.sql" }} -- Dependency for event and payments flows
{{ template "payments/refund_free_event_purchase.sql" }} -- Dependency for leave_event
{{ template "event/leave_event.sql" }}
{{ template "event/list_user_session_proposals_for_cfs_event.sql" }}
{{ template "event/update_event_views.sql" }}

{{ template "group/get_group_full_by_slug.sql" }}
{{ template "group/get_group_past_events.sql" }}
{{ template "group/get_group_upcoming_events.sql" }}
{{ template "group/is_group_member.sql" }}
{{ template "group/join_group.sql" }}
{{ template "group/leave_group.sql" }}
{{ template "group/update_group_views.sql" }}

{{ template "meetings/get_event_meeting_sync_state_hash.sql" }} -- Dependency for meeting sync completion functions
{{ template "meetings/get_session_meeting_sync_state_hash.sql" }} -- Dependency for meeting sync completion functions
{{ template "meetings/add_meeting.sql" }}
{{ template "meetings/assign_zoom_host_user.sql" }}
{{ template "meetings/claim_meeting_for_auto_end.sql" }}
{{ template "meetings/claim_meeting_out_of_sync.sql" }}
{{ template "meetings/delete_meeting.sql" }}
{{ template "meetings/mark_stale_meeting_auto_end_checks_unknown.sql" }}
{{ template "meetings/mark_stale_meeting_syncs_unknown.sql" }}
{{ template "meetings/release_meeting_auto_end_check_claim.sql" }}
{{ template "meetings/release_meeting_sync_claim.sql" }}
{{ template "meetings/set_meeting_auto_end_check_outcome.sql" }}
{{ template "meetings/set_meeting_error.sql" }}
{{ template "meetings/update_meeting.sql" }}
{{ template "meetings/update_meeting_recording_url.sql" }}

{{ template "notifications/claim_pending_notification.sql" }}
{{ template "notifications/enqueue_due_event_reminders.sql" }}
{{ template "notifications/enqueue_notification.sql" }}
{{ template "notifications/mark_stale_processing_notifications_unknown.sql" }}
{{ template "notifications/track_custom_notification.sql" }}
{{ template "notifications/update_notification.sql" }}

{{ template "payments/approve_event_refund_request.sql" }}
{{ template "payments/attach_checkout_session_to_event_purchase.sql" }}
{{ template "payments/begin_event_refund_approval.sql" }}
{{ template "payments/cancel_event_checkout.sql" }}
{{ template "payments/complete_free_event_purchase.sql" }}
{{ template "payments/expire_event_purchase_for_checkout_session.sql" }}
{{ template "payments/prepare_event_checkout_expire_previous_hold.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_expire_stale_holds.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_find_existing_purchase.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_get_purchase_summary.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_reserve_discount_code_availability.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_validate_and_resolve_pricing.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_validate_event.sql" }} -- Dependency for prepare_event_checkout_purchase
{{ template "payments/prepare_event_checkout_purchase.sql" }}
{{ template "payments/reconcile_event_purchase_for_checkout_session.sql" }}
{{ template "payments/record_automatic_refund_for_event_purchase.sql" }}
{{ template "payments/reject_event_refund_request.sql" }}
{{ template "payments/release_event_discount_code_availability.sql" }}
{{ template "payments/request_event_refund.sql" }}
{{ template "payments/revert_event_refund_approval.sql" }}

{{ template "site/get_filters_options.sql" }}
{{ template "site/get_site_home_stats.sql" }}
{{ template "site/get_site_recently_added_groups.sql" }}
{{ template "site/get_site_settings.sql" }}
{{ template "site/get_site_stats.sql" }}
{{ template "site/get_site_upcoming_events.sql" }}
{{ template "site/list_communities.sql" }}

{{ template "triggers/check_session_within_event_bounds.sql" }}
{{ template "triggers/prevent_audit_log_mutation.sql" }}

---- create above / drop below ----

-- Nothing to do
