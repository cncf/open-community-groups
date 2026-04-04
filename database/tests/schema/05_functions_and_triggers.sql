-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(141);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check expected functions exist
select has_function('accept_community_team_invitation');
select has_function('accept_group_team_invitation');
select has_function('accept_session_proposal_co_speaker_invitation');
select has_function('activate_group');
select has_function('add_cfs_submission');
select has_function('add_community_team_member');
select has_function('add_event');
select has_function('add_group');
select has_function('add_group_sponsor');
select has_function('add_group_team_member');
select has_function('add_session_proposal');
select has_function('attend_event');
select has_function('cancel_event');
select has_function('check_in_event');
select has_function('delete_community_team_member');
select has_function('delete_event');
select has_function('delete_group');
select has_function('delete_group_sponsor');
select has_function('delete_group_team_member');
select has_function('delete_session_proposal');
select has_function('escape_ilike_pattern');
select has_function('generate_slug');
select has_function('generate_slug_from_source');
select has_function('get_available_zoom_host_user');
select has_function('get_cfs_submission_notification_data');
select has_function('get_community_full');
select has_function('get_community_id_by_name');
select has_function('get_community_name_by_id');
select has_function('get_community_recently_added_groups');
select has_function('get_community_site_stats');
select has_function('get_community_stats');
select has_function('get_community_upcoming_events');
select has_function('get_event_attendance');
select has_function('get_event_full');
select has_function('get_event_full_by_slug');
select has_function('get_event_summary');
select has_function('get_event_summary_by_id');
select has_function('get_filters_options');
select has_function('get_group_full');
select has_function('get_group_full_by_slug');
select has_function('get_group_past_events');
select has_function('get_group_sponsor');
select has_function('get_group_summary');
select has_function('get_group_upcoming_events');
select has_function('get_meeting_for_auto_end');
select has_function('get_site_home_stats');
select has_function('get_site_recently_added_groups');
select has_function('get_site_settings');
select has_function('get_site_upcoming_events');
select has_function('get_user_by_id');
select has_function('i_array_to_string');
select has_function('insert_audit_log');
select has_function('is_group_member');
select has_function('join_group');
select has_function('leave_event');
select has_function('leave_group');
select has_function('list_communities');
select has_function('list_community_audit_logs');
select has_function('list_community_team_members');
select has_function('list_community_roles');
select has_function('list_cfs_submission_statuses_for_review');
select has_function('list_event_approved_cfs_submissions');
select has_function('list_event_attendees_ids');
select has_function('list_event_categories');
select has_function('list_event_cfs_submissions');
select has_function('list_event_cfs_labels');
select has_function('list_event_kinds');
select has_function('list_event_waitlist_ids');
select has_function('list_group_categories');
select has_function('list_group_audit_logs');
select has_function('list_group_events');
select has_function('list_group_members');
select has_function('list_group_members_ids');
select has_function('list_group_roles');
select has_function('list_group_sponsors');
select has_function('list_group_team_members');
select has_function('list_group_team_members_ids');
select has_function('list_redirects');
select has_function('list_regions');
select has_function('list_session_kinds');
select has_function('list_session_proposal_levels');
select has_function('list_user_audit_logs');
select has_function('list_user_cfs_submissions');
select has_function('list_user_community_team_invitations');
select has_function('list_user_group_team_invitations');
select has_function('list_user_groups');
select has_function('list_user_pending_session_proposal_co_speaker_invitations');
select has_function('list_user_session_proposals');
select has_function('list_user_session_proposals_for_cfs_event');
select has_function('manual_check_in_event');
select has_function('promote_event_waitlist');
select has_function('prevent_audit_log_mutation');
select has_function('publish_event');
select has_function('reject_community_team_invitation');
select has_function('reject_group_team_invitation');
select has_function('reject_session_proposal_co_speaker_invitation');
select has_function('resubmit_cfs_submission');
select has_function('search_event_attendees');
select has_function('search_event_waitlist');
select has_function('search_events');
select has_function('search_groups');
select has_function('search_user');
select has_function('set_meeting_auto_end_check_outcome');
select has_function('sign_up_user');
select has_function('track_custom_notification');
select has_function('unpublish_event');
select has_function('update_cfs_submission');
select has_function('update_community');
select has_function('update_community_team_member_role');
select has_function('update_community_views');
select has_function('update_event');
select has_function('update_event_views');
select has_function('update_group');
select has_function('update_group_sponsor');
select has_function('update_group_team_member_role');
select has_function('update_group_views');
select has_function('update_meeting_recording_url');
select has_function('update_notification');
select has_function('update_session_proposal');
select has_function('update_user_details');
select has_function('user_has_community_permission');
select has_function('user_has_group_permission');
select has_function('verify_email');
select has_function('withdraw_cfs_submission');

-- Test: check expected trigger functions exist
select has_function('check_event_attendee_waitlist');
select has_function('check_event_category_community');
select has_function('check_event_sponsor_group');
select has_function('check_event_waitlist_attendee');
select has_function('check_group_category_community');
select has_function('check_group_region_community');
select has_function('check_session_cfs_submission_approved');
select has_function('check_session_within_event_bounds');

-- Test: check expected triggers exist
select has_trigger('audit_log', 'audit_log_mutation_guard');
select has_trigger('event_attendee', 'event_attendee_waitlist_check');
select has_trigger('event', 'event_category_community_check');
select has_trigger('event_sponsor', 'event_sponsor_group_check');
select has_trigger('event_waitlist', 'event_waitlist_attendee_check');
select has_trigger('group', 'group_category_community_check');
select has_trigger('group', 'group_region_community_check');
select has_trigger('session', 'session_cfs_submission_approved_check');
select has_trigger('session', 'session_within_event_bounds_check');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
