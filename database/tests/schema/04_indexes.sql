-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(55);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: attachment indexes should match expected
select indexes_are('attachment', array[
    'attachment_pkey',
    'attachment_hash_idx'
]);

-- Test: auth_session indexes should match expected
select indexes_are('auth_session', array[
    'auth_session_pkey'
]);

-- Test: cfs_submission indexes should match expected
select indexes_are('cfs_submission', array[
    'cfs_submission_pkey',
    'cfs_submission_event_id_idx',
    'cfs_submission_event_id_session_proposal_id_key',
    'cfs_submission_reviewed_by_idx',
    'cfs_submission_session_proposal_id_idx',
    'cfs_submission_status_id_idx'
]);

-- Test: cfs_submission_label indexes should match expected
select indexes_are('cfs_submission_label', array[
    'cfs_submission_label_pkey',
    'cfs_submission_label_event_cfs_label_id_idx'
]);

-- Test: cfs_submission_rating indexes should match expected
select indexes_are('cfs_submission_rating', array[
    'cfs_submission_rating_pkey',
    'cfs_submission_rating_reviewer_id_idx'
]);

-- Test: cfs_submission_status indexes should match expected
select indexes_are('cfs_submission_status', array[
    'cfs_submission_status_pkey',
    'cfs_submission_status_display_name_key'
]);

-- Test: community indexes should match expected
select indexes_are('community', array[
    'community_pkey',
    'community_community_site_layout_id_idx',
    'community_display_name_key',
    'community_name_key'
]);

-- Test: community_site_layout indexes should match expected
select indexes_are('community_site_layout', array[
    'community_site_layout_pkey'
]);

-- Test: community_role indexes should match expected
select indexes_are('community_role', array[
    'community_role_pkey',
    'community_role_display_name_key'
]);

-- Test: community_permission indexes should match expected
select indexes_are('community_permission', array[
    'community_permission_pkey',
    'community_permission_display_name_key'
]);

-- Test: community_role_community_permission indexes should match expected
select indexes_are('community_role_community_permission', array[
    'community_role_community_permission_pkey'
]);

-- Test: community_role_group_permission indexes should match expected
select indexes_are('community_role_group_permission', array[
    'community_role_group_permission_pkey'
]);

-- Test: community_team indexes should match expected
select indexes_are('community_team', array[
    'community_team_pkey',
    'community_team_community_id_idx',
    'community_team_role_idx',
    'community_team_user_id_idx',
    'community_team_pending_user_created_at_idx'
]);

-- Test: community_views indexes should match expected
select indexes_are('community_views', array[
    'community_views_community_id_day_key'
]);

-- Test: custom_notification indexes should match expected
select indexes_are('custom_notification', array[
    'custom_notification_created_by_idx',
    'custom_notification_event_id_idx',
    'custom_notification_group_id_idx',
    'custom_notification_pkey'
]);

-- Test: email_verification_code indexes should match expected
select indexes_are('email_verification_code', array[
    'email_verification_code_pkey',
    'email_verification_code_user_id_idx',
    'email_verification_code_user_id_key'
]);

-- Test: event indexes should match expected
select indexes_are('event', array[
    'event_pkey',
    'event_slug_group_id_key',
    'event_event_category_id_idx',
    'event_event_kind_id_idx',
    'event_group_id_idx',
    'event_location_idx',
    'event_meeting_sync_idx',
    'event_published_by_idx',
    'event_search_idx',
    'event_starts_at_idx',
    'event_tsdoc_idx',
    'event_group_not_deleted_starts_at_idx'
]);

-- Test: event_attendee indexes should match expected
select indexes_are('event_attendee', array[
    'event_attendee_pkey',
    'event_attendee_event_id_idx',
    'event_attendee_user_id_idx',
    'event_attendee_event_id_created_at_idx'
]);

-- Test: event_category indexes should match expected
select indexes_are('event_category', array[
    'event_category_pkey',
    'event_category_name_community_id_key',
    'event_category_slug_community_id_key',
    'event_category_community_id_idx'
]);

-- Test: event_host indexes should match expected
select indexes_are('event_host', array[
    'event_host_pkey',
    'event_host_event_id_idx',
    'event_host_user_id_idx'
]);

-- Test: event_kind indexes should match expected
select indexes_are('event_kind', array[
    'event_kind_pkey',
    'event_kind_display_name_key'
]);

-- Test: event_cfs_label indexes should match expected
select indexes_are('event_cfs_label', array[
    'event_cfs_label_pkey',
    'event_cfs_label_event_id_name_key',
    'event_cfs_label_event_id_idx'
]);

-- Test: group indexes should match expected
select indexes_are('group', array[
    'group_pkey',
    'group_slug_community_id_key',
    'group_community_id_idx',
    'group_group_category_id_idx',
    'group_region_id_idx',
    'group_group_site_layout_id_idx',
    'group_location_idx',
    'group_search_idx',
    'group_tsdoc_idx',
    'group_active_created_at_idx',
    'group_community_active_created_at_idx'
]);

-- Test: group_category indexes should match expected
select indexes_are('group_category', array[
    'group_category_pkey',
    'group_category_name_community_id_key',
    'group_category_normalized_name_community_id_key',
    'group_category_community_id_idx'
]);

-- Test: group_member indexes should match expected
select indexes_are('group_member', array[
    'group_member_pkey',
    'group_member_group_id_idx',
    'group_member_user_id_idx',
    'group_member_group_id_created_at_idx'
]);

-- Test: group_role indexes should match expected
select indexes_are('group_role', array[
    'group_role_pkey',
    'group_role_display_name_key'
]);

-- Test: group_permission indexes should match expected
select indexes_are('group_permission', array[
    'group_permission_pkey',
    'group_permission_display_name_key'
]);

-- Test: group_role_group_permission indexes should match expected
select indexes_are('group_role_group_permission', array[
    'group_role_group_permission_pkey'
]);

-- Test: group_site_layout indexes should match expected
select indexes_are('group_site_layout', array[
    'group_site_layout_pkey'
]);

-- Test: group_sponsor indexes should match expected
select indexes_are('group_sponsor', array[
    'group_sponsor_pkey',
    'group_sponsor_group_id_idx'
]);

-- Test: event_speaker indexes should match expected
select indexes_are('event_speaker', array[
    'event_speaker_pkey',
    'event_speaker_event_id_idx',
    'event_speaker_user_id_idx'
]);

-- Test: event_sponsor indexes should match expected
select indexes_are('event_sponsor', array[
    'event_sponsor_pkey',
    'event_sponsor_event_id_idx',
    'event_sponsor_group_sponsor_id_idx'
]);

-- Test: event_views indexes should match expected
select indexes_are('event_views', array[
    'event_views_event_id_day_key'
]);

-- Test: event_waitlist indexes should match expected
select indexes_are('event_waitlist', array[
    'event_waitlist_pkey',
    'event_waitlist_user_id_idx',
    'event_waitlist_event_id_created_at_idx'
]);

-- Test: group_team indexes should match expected
select indexes_are('group_team', array[
    'group_team_pkey',
    'group_team_group_id_idx',
    'group_team_user_id_idx',
    'group_team_role_idx',
    'group_team_pending_user_created_at_idx'
]);

-- Test: group_views indexes should match expected
select indexes_are('group_views', array[
    'group_views_group_id_day_key'
]);

-- Test: images indexes should match expected
select indexes_are('images', array[
    'images_pkey'
]);

-- Test: legacy_event_host indexes should match expected
select indexes_are('legacy_event_host', array[
    'legacy_event_host_pkey',
    'legacy_event_host_event_id_idx'
]);

-- Test: legacy_event_speaker indexes should match expected
select indexes_are('legacy_event_speaker', array[
    'legacy_event_speaker_pkey',
    'legacy_event_speaker_event_id_idx'
]);

-- Test: meeting indexes should match expected
select indexes_are('meeting', array[
    'meeting_event_id_idx',
    'meeting_meeting_provider_id_idx',
    'meeting_meeting_provider_id_provider_meeting_id_idx',
    'meeting_meeting_provider_id_provider_host_user_id_idx',
    'meeting_pkey',
    'meeting_session_id_idx',
    'meeting_zoom_auto_end_pending_idx'
]);

-- Test: meeting_auto_end_check_outcome indexes should match expected
select indexes_are('meeting_auto_end_check_outcome', array[
    'meeting_auto_end_check_outcome_pkey',
    'meeting_auto_end_check_outcome_display_name_key'
]);

-- Test: meeting_provider indexes should match expected
select indexes_are('meeting_provider', array[
    'meeting_provider_display_name_key',
    'meeting_provider_pkey'
]);

-- Test: notification indexes should match expected
select indexes_are('notification', array[
    'notification_pkey',
    'notification_kind_idx',
    'notification_not_processed_idx',
    'notification_user_id_idx'
]);

-- Test: notification_attachment indexes should match expected
select indexes_are('notification_attachment', array[
    'notification_attachment_pkey',
    'notification_attachment_attachment_id_idx'
]);

-- Test: notification_kind indexes should match expected
select indexes_are('notification_kind', array[
    'notification_kind_name_key',
    'notification_kind_pkey'
]);

-- Test: notification_template_data indexes should match expected
select indexes_are('notification_template_data', array[
    'notification_template_data_hash_idx',
    'notification_template_data_pkey'
]);

-- Test: region indexes should match expected
select indexes_are('region', array[
    'region_pkey',
    'region_name_community_id_key',
    'region_normalized_name_community_id_key',
    'region_community_id_idx'
]);

-- Test: session indexes should match expected
select indexes_are('session', array[
    'session_pkey',
    'session_cfs_submission_id_unique_idx',
    'session_event_id_idx',
    'session_meeting_sync_idx',
    'session_session_kind_id_idx'
]);

-- Test: session_proposal indexes should match expected
select indexes_are('session_proposal', array[
    'session_proposal_pkey',
    'session_proposal_co_speaker_user_id_idx',
    'session_proposal_session_proposal_level_id_idx',
    'session_proposal_status_id_idx',
    'session_proposal_user_id_idx'
]);

-- Test: session_proposal_level indexes should match expected
select indexes_are('session_proposal_level', array[
    'session_proposal_level_display_name_key',
    'session_proposal_level_pkey'
]);

-- Test: session_proposal_status indexes should match expected
select indexes_are('session_proposal_status', array[
    'session_proposal_status_display_name_key',
    'session_proposal_status_pkey'
]);

-- Test: session_speaker indexes should match expected
select indexes_are('session_speaker', array[
    'session_speaker_pkey',
    'session_speaker_session_id_idx',
    'session_speaker_user_id_idx'
]);

-- Test: session_kind indexes should match expected
select indexes_are('session_kind', array[
    'session_kind_pkey',
    'session_kind_display_name_key'
]);

-- Test: site indexes should match expected
select indexes_are('site', array[
    'site_pkey'
]);

-- Test: user indexes should match expected
select indexes_are('user', array[
    'user_pkey',
    'user_email_key',
    'user_email_lower_idx',
    'user_name_lower_idx',
    'user_username_key',
    'user_username_lower_idx'
]);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
