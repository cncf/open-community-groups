-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(281);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f0050000-0000-0000-0000-000000000001'
\set discountCodeID 'f0050000-0000-0000-0000-000000000002'
\set eventCategoryID 'f0050000-0000-0000-0000-000000000003'
\set eventID 'f0050000-0000-0000-0000-000000000004'
\set groupCategoryID 'f0050000-0000-0000-0000-000000000005'
\set groupID 'f0050000-0000-0000-0000-000000000006'
\set ticketTypeID 'f0050000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conferences');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    timezone
) values (
    :'eventID',
    'Test Event',
    'test-event',
    'A test event',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check expected functions exist
select has_function('accept_community_team_invitation', array['uuid', 'uuid']::name[]);
select has_function('accept_event_attendee_invitation', array['uuid', 'uuid']::name[]);
select has_function('accept_event_invitation_request', array['uuid', 'uuid', 'uuid', 'uuid']::name[]);
select has_function('accept_group_team_invitation', array['uuid', 'uuid']::name[]);
select has_function('accept_session_proposal_co_speaker_invitation', array['uuid', 'uuid']::name[]);
select has_function('activate_group', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('activate_pre_registered_user_email_password', array['jsonb', 'uuid', 'jsonb']::name[]);
select has_function('activate_pre_registered_user_external_provider', array['uuid', 'jsonb']::name[]);
select has_function('add_cfs_submission', array['uuid', 'uuid', 'uuid', 'uuid', 'uuid[]']::name[]);
select has_function('add_community_team_member', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('add_event', array['uuid', 'uuid', 'jsonb', 'jsonb']::name[]);
select has_function('add_event_category', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('add_event_series', array['uuid', 'uuid', 'jsonb', 'jsonb', 'jsonb']::name[]);
select has_function('add_group', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('add_group_category', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('add_group_sponsor', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('add_group_team_member', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('add_meeting', array['text', 'text', 'text', 'text', 'text', 'uuid', 'uuid', 'timestamp with time zone', 'text']::name[]);
select has_function('add_region', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('add_session_proposal', array['uuid', 'jsonb']::name[]);
select has_function('append_meeting_recording_url', array['text', 'text', 'text']::name[]);
select has_function('approve_event_refund_request', array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text']::name[]);
select has_function('assign_zoom_host_user', array['uuid', 'uuid', 'timestamp with time zone', 'text[]', 'integer', 'timestamp with time zone', 'timestamp with time zone']::name[]);
select has_function('attach_checkout_session_to_event_purchase', array['uuid', 'text', 'text', 'text']::name[]);
select has_function('attend_event', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('begin_event_refund_approval', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('cancel_event', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('cancel_event_attendee_attendance', array['uuid', 'uuid', 'uuid', 'uuid']::name[]);
select has_function('cancel_event_attendee_invitation', array['uuid', 'uuid', 'uuid', 'uuid']::name[]);
select has_function('cancel_event_checkout', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('cancel_event_series_events', array['uuid', 'uuid', 'uuid[]']::name[]);
select has_function('check_in_event', array['uuid', 'uuid', 'uuid', 'boolean']::name[]);
select has_function('claim_meeting_for_auto_end', '{}'::name[]);
select has_function('claim_meeting_out_of_sync', '{}'::name[]);
select has_function('claim_pending_notification', array['integer', 'integer']::name[]);
select has_function('complete_free_event_purchase', array['uuid']::name[]);
select has_function('deactivate_group', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_community_team_member', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_event', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_event_category', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_event_series_events', array['uuid', 'uuid', 'uuid[]']::name[]);
select has_function('delete_group', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_group_category', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_group_sponsor', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_group_team_member', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_meeting', array['uuid', 'uuid', 'uuid', 'timestamp with time zone', 'text']::name[]);
select has_function('delete_region', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('delete_session_proposal', array['uuid', 'uuid']::name[]);
select has_function('enqueue_due_event_reminders', array['text']::name[]);
select has_function('enqueue_notification', array['text', 'jsonb', 'jsonb', 'uuid[]']::name[]);
select has_function('enqueue_tracked_custom_notification', array['text', 'jsonb', 'jsonb', 'uuid[]', 'uuid', 'uuid', 'uuid', 'integer', 'text', 'text']::name[]);
select has_function('ensure_event_is_active', array['uuid', 'uuid']::name[]);
select has_function('escape_ilike_pattern', array['text']::name[]);
select has_function('expire_event_purchase_for_checkout_session', array['text', 'text']::name[]);
select has_function('generate_slug', array['integer']::name[]);
select has_function('generate_slug_from_source', array['text', 'integer']::name[]);
select has_function('get_cfs_submission_notification_data', array['uuid', 'uuid']::name[]);
select has_function('get_community_full', array['uuid']::name[]);
select has_function('get_community_id_by_name', array['text']::name[]);
select has_function('get_community_name_by_id', array['uuid']::name[]);
select has_function('get_community_recently_added_groups', array['uuid']::name[]);
select has_function('get_community_site_stats', array['uuid']::name[]);
select has_function('get_community_stats', array['uuid']::name[]);
select has_function('get_community_summary', array['uuid']::name[]);
select has_function('get_community_upcoming_events', array['uuid', 'text[]']::name[]);
select has_function('get_event_attendance', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('get_event_full', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('get_event_full_by_slug', array['uuid', 'text', 'text']::name[]);
select has_function('get_event_meeting_sync_state_hash', array['uuid']::name[]);
select has_function('get_event_occupied_seat_count', array['uuid']::name[]);
select has_function('get_event_registration_questions', array['uuid', 'uuid']::name[]);
select has_function('get_event_summary', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('get_event_summary_by_id', array['uuid', 'uuid']::name[]);
select has_function('get_event_summary_dashboard', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('get_event_ticket_capacity', array['jsonb']::name[]);
select has_function('get_filters_options', array['text', 'text']::name[]);
select has_function('get_group_full', array['uuid', 'uuid']::name[]);
select has_function('get_group_full_by_slug', array['uuid', 'text']::name[]);
select has_function('get_group_past_events', array['uuid', 'text', 'text[]', 'integer']::name[]);
select has_function('get_group_sponsor', array['uuid', 'uuid']::name[]);
select has_function('get_group_stats', array['uuid', 'uuid']::name[]);
select has_function('get_group_summary', array['uuid', 'uuid']::name[]);
select has_function('get_group_upcoming_events', array['uuid', 'text', 'text[]', 'integer']::name[]);
select has_function('get_public_user_provider', array['jsonb']::name[]);
select has_function('get_session_meeting_sync_state_hash', array['uuid']::name[]);
select has_function('get_site_home_stats', '{}'::name[]);
select has_function('get_site_recently_added_groups', '{}'::name[]);
select has_function('get_site_settings', '{}'::name[]);
select has_function('get_site_stats', '{}'::name[]);
select has_function('get_site_upcoming_events', array['text[]']::name[]);
select has_function('get_user_by_email', array['text']::name[]);
select has_function('get_user_by_email_for_external_auth', array['text']::name[]);
select has_function('get_user_by_id', array['uuid', 'boolean']::name[]);
select has_function('get_user_by_id_verified', array['uuid']::name[]);
select has_function(
    'get_user_by_linuxfoundation_identity_for_external_auth',
    array['text', 'text']::name[]
);
select has_function('get_user_by_username', array['text']::name[]);
select has_function('i_array_to_string', array['text[]', 'text']::name[]);
select has_function('insert_audit_log', array['text', 'uuid', 'text', 'uuid', 'uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('invite_event_attendee', array['uuid', 'uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('is_event_check_in_window_open', array['uuid', 'uuid']::name[]);
select has_function('is_event_meeting_in_sync', array['jsonb', 'jsonb']::name[]);
select has_function('is_group_member', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('is_open_graph_image', array['text']::name[]);
select has_function(
    'is_registration_window_open',
    array['timestamp with time zone', 'timestamp with time zone', 'timestamp with time zone']::name[]
);
select has_function('is_session_meeting_in_sync', array['jsonb', 'jsonb', 'jsonb', 'jsonb']::name[]);
select has_function('join_group', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('jsonb_geography_point', array['jsonb']::name[]);
select has_function('jsonb_text_array', array['jsonb']::name[]);
select has_function('leave_event', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('leave_group', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('list_cfs_submission_statuses_for_review', '{}'::name[]);
select has_function('list_communities', '{}'::name[]);
select has_function('list_community_audit_logs', array['uuid', 'jsonb']::name[]);
select has_function('list_community_roles', '{}'::name[]);
select has_function('list_community_team_members', array['uuid', 'jsonb']::name[]);
select has_function('list_event_approved_cfs_submissions', array['uuid']::name[]);
select has_function('list_event_attendees_ids', array['uuid', 'uuid']::name[]);
select has_function('list_event_categories', array['uuid']::name[]);
select has_function('list_event_cfs_labels', array['uuid']::name[]);
select has_function('list_event_cfs_submissions', array['uuid', 'jsonb']::name[]);
select has_function('list_event_discount_codes', array['uuid']::name[]);
select has_function('list_event_kinds', '{}'::name[]);
select has_function('list_event_series_event_ids', array['uuid', 'uuid']::name[]);
select has_function('list_event_series_publishable_event_ids', array['uuid', 'uuid']::name[]);
select has_function('list_event_ticket_types', array['uuid']::name[]);
select has_function('list_event_waitlist_ids', array['uuid', 'uuid']::name[]);
select has_function('list_group_audit_logs', array['uuid', 'jsonb']::name[]);
select has_function('list_group_categories', array['uuid']::name[]);
select has_function('list_group_events', array['uuid', 'jsonb']::name[]);
select has_function('list_group_members', array['uuid', 'jsonb']::name[]);
select has_function('list_group_members_ids', array['uuid']::name[]);
select has_function('list_group_roles', '{}'::name[]);
select has_function('list_group_sponsors', array['uuid', 'jsonb', 'boolean']::name[]);
select has_function('list_group_team_members', array['uuid', 'jsonb']::name[]);
select has_function('list_group_team_members_ids', array['uuid']::name[]);
select has_function('list_payment_currency_codes', '{}'::name[]);
select has_function('list_redirect_communities', '{}'::name[]);
select has_function('list_redirects', '{}'::name[]);
select has_function('list_regions', array['uuid']::name[]);
select has_function('list_session_kinds', '{}'::name[]);
select has_function('list_session_proposal_levels', '{}'::name[]);
select has_function('list_user_audit_logs', array['uuid', 'jsonb']::name[]);
select has_function('list_user_cfs_submissions', array['uuid', 'jsonb']::name[]);
select has_function('list_user_communities', array['uuid']::name[]);
select has_function('list_user_community_team_invitations', array['uuid']::name[]);
select has_function('list_user_event_invitations', array['uuid']::name[]);
select has_function('list_user_events', array['uuid', 'jsonb']::name[]);
select has_function('list_user_group_team_invitations', array['uuid']::name[]);
select has_function('list_user_groups', array['uuid']::name[]);
select has_function('list_user_pending_session_proposal_co_speaker_invitations', array['uuid']::name[]);
select has_function('list_user_session_proposals', array['uuid', 'jsonb']::name[]);
select has_function('list_user_session_proposals_for_cfs_event', array['uuid', 'uuid']::name[]);
select has_function('manual_check_in_event', array['uuid', 'uuid', 'uuid', 'uuid']::name[]);
select has_function('mark_stale_meeting_auto_end_checks_unknown', array['bigint']::name[]);
select has_function('mark_stale_meeting_syncs_unknown', array['bigint']::name[]);
select has_function('mark_stale_processing_notifications_unknown', array['bigint']::name[]);
select has_function('prepare_event_checkout_expire_previous_hold', array['uuid']::name[]);
select has_function('prepare_event_checkout_expire_stale_holds', array['uuid']::name[]);
select has_function('prepare_event_checkout_find_existing_purchase', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('prepare_event_checkout_get_purchase_summary', array['uuid']::name[]);
select has_function('prepare_event_checkout_purchase', array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'jsonb']::name[]);
select has_function('prepare_event_checkout_reserve_discount_code_availability', array['uuid']::name[]);
select has_function('prepare_event_checkout_validate_and_resolve_pricing', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('prepare_event_checkout_validate_attendee_state', array['uuid', 'uuid']::name[]);
select has_function('prepare_event_checkout_validate_event', array['uuid', 'uuid', 'text']::name[]);
select has_function('promote_event_waitlist', array['uuid', 'integer']::name[]);
select has_function('publish_event', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('publish_event_series_events', array['uuid', 'uuid', 'uuid[]', 'text']::name[]);
select has_function('questionnaire_answers_exist_for_event', array['uuid']::name[]);
select has_function('reconcile_event_purchase_for_checkout_session', array['text', 'text', 'text']::name[]);
select has_function('record_automatic_refund_for_event_purchase', array['uuid', 'text']::name[]);
select has_function('refund_free_event_purchase', array['uuid']::name[]);
select has_function('reject_community_team_invitation', array['uuid', 'uuid']::name[]);
select has_function('reject_event_attendee_invitation', array['uuid', 'uuid']::name[]);
select has_function('reject_event_invitation_request', array['uuid', 'uuid', 'uuid', 'uuid']::name[]);
select has_function('reject_event_refund_request', array['uuid', 'uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('reject_group_team_invitation', array['uuid', 'uuid']::name[]);
select has_function('reject_session_proposal_co_speaker_invitation', array['uuid', 'uuid']::name[]);
select has_function('release_event_checkout_attendee_hold', array['uuid', 'uuid']::name[]);
select has_function('release_event_discount_code_availability', array['uuid', 'integer']::name[]);
select has_function('release_meeting_auto_end_check_claim', array['timestamp with time zone', 'uuid']::name[]);
select has_function('release_meeting_sync_claim', array['uuid', 'uuid', 'uuid', 'timestamp with time zone']::name[]);
select has_function('request_event_refund', array['uuid', 'uuid', 'uuid', 'text', 'jsonb']::name[]);
select has_function('resolve_event_custom_notification_recipient_ids', array['uuid', 'uuid', 'text', 'uuid[]']::name[]);
select has_function('resolve_unique_username', array['text', 'uuid']::name[]);
select has_function('resubmit_cfs_submission', array['uuid', 'uuid']::name[]);
select has_function('revert_event_refund_approval', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('search_event_attendees', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('search_event_invitation_requests', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('search_event_waitlist', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('search_events', array['jsonb']::name[]);
select has_function('search_groups', array['jsonb']::name[]);
select has_function('search_user', array['text']::name[]);
select has_function('set_meeting_auto_end_check_outcome', array['timestamp with time zone', 'uuid', 'text']::name[]);
select has_function('set_meeting_error', array['text', 'uuid', 'uuid', 'uuid', 'timestamp with time zone', 'text']::name[]);
select has_function('sign_up_user', array['jsonb', 'boolean', 'uuid', 'jsonb']::name[]);
select has_function('stats_label_count_series', array['jsonb']::name[]);
select has_function('stats_label_count_series_by_name', array['jsonb']::name[]);
select has_function('stats_running_total_series', array['jsonb']::name[]);
select has_function('stats_running_total_series_by_name', array['jsonb']::name[]);
select has_function('submit_event_registration_answers', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('sync_cfs_submission_labels', array['uuid', 'uuid', 'uuid[]']::name[]);
select has_function('sync_event_cfs_labels', array['uuid', 'jsonb']::name[]);
select has_function('sync_event_discount_codes', array['uuid', 'jsonb']::name[]);
select has_function('sync_event_hosts_speakers_sponsors', array['uuid', 'jsonb']::name[]);
select has_function('sync_event_sessions', array['uuid', 'jsonb', 'jsonb']::name[]);
select has_function('sync_event_ticket_types', array['uuid', 'jsonb']::name[]);
select has_function('track_custom_notification', array['uuid', 'uuid', 'uuid', 'integer', 'text', 'text']::name[]);
select has_function('unpublish_event', array['uuid', 'uuid', 'uuid']::name[]);
select has_function('unpublish_event_series_events', array['uuid', 'uuid', 'uuid[]']::name[]);
select has_function('update_cfs_submission', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_community', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_community_team_member_role', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('update_community_views', array['jsonb']::name[]);
select has_function('update_event', array['uuid', 'uuid', 'uuid', 'jsonb', 'jsonb']::name[]);
select has_function('update_event_category', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_event_views', array['jsonb']::name[]);
select has_function('update_group', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_group_category', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_group_sponsor', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_group_sponsor_featured', array['uuid', 'uuid', 'uuid', 'boolean']::name[]);
select has_function('update_group_team_member_role', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('update_group_views', array['jsonb']::name[]);
select has_function('update_meeting', array['uuid', 'text', 'text', 'text', 'uuid', 'uuid', 'timestamp with time zone', 'text']::name[]);
select has_function('update_notification', array['uuid', 'text']::name[]);
select has_function('update_region', array['uuid', 'uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_session_proposal', array['uuid', 'uuid', 'jsonb']::name[]);
select has_function('update_user_details', array['uuid', 'jsonb']::name[]);
select has_function('update_user_external_auth', array['uuid', 'jsonb']::name[]);
select has_function('update_user_password', array['uuid', 'text']::name[]);
select has_function('update_user_provider', array['uuid', 'jsonb']::name[]);
select has_function('upsert_pending_registration_answers', array['uuid', 'uuid', 'jsonb', 'jsonb']::name[]);
select has_function('user_has_community_permission', array['uuid', 'uuid', 'text']::name[]);
select has_function('user_has_group_permission', array['uuid', 'uuid', 'uuid', 'text']::name[]);
select has_function('validate_add_event_dates', array['jsonb']::name[]);
select has_function('validate_cfs_submission_label_ids', array['uuid', 'uuid[]']::name[]);
select has_function('validate_event_capacity', array['jsonb', 'jsonb', 'uuid', 'integer']::name[]);
select has_function('validate_event_cfs_labels_payload', array['jsonb']::name[]);
select has_function('validate_event_discount_codes_payload', array['jsonb']::name[]);
select has_function('validate_event_enrollment_payload', array['boolean', 'jsonb', 'boolean']::name[]);
select has_function('validate_event_series_action_event_ids', array['uuid', 'uuid[]', 'boolean']::name[]);
select has_function('validate_event_ticket_types_payload', array['jsonb']::name[]);
select has_function('validate_event_ticketing_payload', array['jsonb', 'text', 'jsonb', 'boolean']::name[]);
select has_function('validate_payment_amount', array['text', 'bigint']::name[]);
select has_function('validate_payment_currency_code', array['text']::name[]);
select has_function('validate_questionnaire_answers_payload', array['jsonb', 'jsonb']::name[]);
select has_function('validate_questionnaire_questions_payload', array['jsonb']::name[]);
select has_function('validate_update_event_dates', array['jsonb', 'jsonb']::name[]);
select has_function('verify_email', array['uuid']::name[]);
select has_function('withdraw_cfs_submission', array['uuid', 'uuid']::name[]);

-- Test: check expected trigger functions exist
select has_function('check_event_attendee_waitlist', '{}'::name[]);
select has_function('check_event_category_community', '{}'::name[]);
select has_function('check_event_sponsor_group', '{}'::name[]);
select has_function('check_event_ticketing_consistency', '{}'::name[]);
select has_function('check_event_waitlist_attendee', '{}'::name[]);
select has_function('check_group_category_community', '{}'::name[]);
select has_function('check_group_region_community', '{}'::name[]);
select has_function('check_session_cfs_submission_approved', '{}'::name[]);
select has_function('check_session_within_event_bounds', '{}'::name[]);
select has_function('prevent_audit_log_mutation', '{}'::name[]);
select has_function('validate_group_slug_pretty', '{}'::name[]);

-- Test: check expected triggers exist
select has_trigger('audit_log', 'audit_log_mutation_guard');
select has_trigger('event_attendee', 'event_attendee_waitlist_check');
select has_trigger('event', 'event_category_community_check');
select has_trigger('event', 'event_ticketing_consistency_on_event');
select has_trigger('event_discount_code', 'event_ticketing_consistency_on_event_discount_code');
select has_trigger('event_sponsor', 'event_sponsor_group_check');
select has_trigger('event_ticket_type', 'event_ticketing_consistency_on_event_ticket_type');
select has_trigger('event_waitlist', 'event_waitlist_attendee_check');
select has_trigger('group', 'group_category_community_check');
select has_trigger('group', 'group_region_community_check');
select has_trigger('group', 'group_slug_pretty_validate');
select has_trigger('session', 'session_cfs_submission_approved_check');
select has_trigger('session', 'session_within_event_bounds_check');

-- Test: event ticketing consistency triggers should enforce the ticketing shape
-- Check the deferred constraint triggers at the end of each statement
set constraints
    event_ticketing_consistency_on_event,
    event_ticketing_consistency_on_event_discount_code,
    event_ticketing_consistency_on_event_ticket_type
    immediate;

-- Should reject ticket types when the event has no payment currency
select throws_ok(
    format($$
        insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
        values (%L, %L, 1, 10, 'General')
    $$, :'ticketTypeID', :'eventID'),
    'ticketed events require payment_currency_code',
    'Ticket types should require a payment currency on the event'
);

-- Should reject discount codes when the event has no ticket types
select throws_ok(
    format($$
        insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
        values (%L, %L, 'SAVE10', 'fixed_amount', 'Launch', 500)
    $$, :'discountCodeID', :'eventID'),
    'discount_codes require ticket_types',
    'Discount codes should require ticket types on the event'
);

-- Should reject a payment currency when the event has no ticket types
select throws_ok(
    format($$
        update event
        set payment_currency_code = 'USD'
        where event_id = %L
    $$, :'eventID'),
    'payment_currency_code requires ticket_types',
    'Payment currency should require ticket types on the event'
);

-- Should accept a payment currency and a ticket type written together
select lives_ok(
    format($$
        with currency as (
            update event
            set payment_currency_code = 'USD'
            where event_id = %L
        )
        insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
        values (%L, %L, 1, 10, 'General')
    $$, :'eventID', :'ticketTypeID', :'eventID'),
    'Payment currency and ticket types written together should be accepted'
);

-- Should reject removing the last ticket type while the payment currency remains
select throws_ok(
    format($$
        delete from event_ticket_type
        where event_ticket_type_id = %L
    $$, :'ticketTypeID'),
    'payment_currency_code requires ticket_types',
    'Removing the last ticket type should be rejected while the payment currency remains'
);

-- Should accept discount codes once ticket types exist
select lives_ok(
    format($$
        insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
        values (%L, %L, 'SAVE10', 'fixed_amount', 'Launch', 500)
    $$, :'discountCodeID', :'eventID'),
    'Discount codes should be accepted once ticket types exist'
);

-- Should accept deleting an event along with its ticketing rows
select lives_ok(
    format($$
        delete from event
        where event_id = %L
    $$, :'eventID'),
    'Deleting an event along with its ticketing rows should be accepted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
