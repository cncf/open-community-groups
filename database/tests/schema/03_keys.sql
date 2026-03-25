-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(130);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check tables have expected primary keys
select has_pk('attachment');
select has_pk('audit_log');
select has_pk('auth_session');
select has_pk('cfs_submission');
select has_pk('cfs_submission_rating');
select has_pk('cfs_submission_status');
select has_pk('community');
select has_pk('community_permission');
select has_pk('community_role');
select has_pk('community_role_community_permission');
select has_pk('community_role_group_permission');
select has_pk('community_site_layout');
select has_pk('community_team');
select hasnt_pk('community_views');
select has_pk('custom_notification');
select has_pk('email_verification_code');
select has_pk('event');
select has_pk('event_attendee');
select has_pk('event_category');
select has_pk('event_host');
select has_pk('event_kind');
select has_pk('event_speaker');
select has_pk('event_sponsor');
select hasnt_pk('event_views');
select has_pk('event_waitlist');
select has_pk('group');
select has_pk('group_category');
select has_pk('group_member');
select has_pk('group_permission');
select has_pk('group_role');
select has_pk('group_role_group_permission');
select has_pk('group_site_layout');
select has_pk('group_sponsor');
select has_pk('group_team');
select hasnt_pk('group_views');
select has_pk('images');
select has_pk('legacy_event_host');
select has_pk('legacy_event_speaker');
select has_pk('meeting');
select has_pk('meeting_auto_end_check_outcome');
select has_pk('meeting_provider');
select has_pk('notification');
select has_pk('notification_attachment');
select has_pk('notification_kind');
select has_pk('notification_template_data');
select has_pk('region');
select has_pk('session');
select has_pk('session_kind');
select has_pk('session_proposal');
select has_pk('session_proposal_level');
select has_pk('session_proposal_status');
select has_pk('session_speaker');
select has_pk('site');
select has_pk('user');

-- Test: check tables have expected foreign keys
select col_is_fk('community', 'community_site_layout_id', 'community_site_layout');
select col_is_fk('audit_log', 'actor_user_id', 'user');
select col_is_fk('audit_log', 'community_id', 'community');
select col_is_fk('audit_log', 'event_id', 'event');
select col_is_fk('audit_log', 'group_id', 'group');
select col_is_fk('community_role_community_permission', 'community_permission_id', 'community_permission');
select col_is_fk('community_role_community_permission', 'community_role_id', 'community_role');
select col_is_fk('community_role_group_permission', 'community_role_id', 'community_role');
select col_is_fk('community_role_group_permission', 'group_permission_id', 'group_permission');
select col_is_fk('community_team', 'community_id', 'community');
select col_is_fk('community_team', 'user_id', 'user');
select col_is_fk('community_views', 'community_id', 'community');
select col_is_fk('custom_notification', 'created_by', 'user');
select col_is_fk('custom_notification', 'event_id', 'event');
select col_is_fk('custom_notification', 'group_id', 'group');
select col_is_fk('cfs_submission', 'event_id', 'event');
select col_is_fk('cfs_submission', 'reviewed_by', 'user');
select col_is_fk('cfs_submission', 'session_proposal_id', 'session_proposal');
select col_is_fk('cfs_submission', 'status_id', 'cfs_submission_status');
select col_is_fk('cfs_submission_rating', 'cfs_submission_id', 'cfs_submission');
select col_is_fk('cfs_submission_rating', 'reviewer_id', 'user');
select col_is_fk('email_verification_code', 'user_id', 'user');
select col_is_fk('event', 'event_category_id', 'event_category');
select col_is_fk('event', 'event_kind_id', 'event_kind');
select col_is_fk('event', 'group_id', 'group');
select col_is_fk('event', 'meeting_provider_id', 'meeting_provider');
select col_is_fk('event', 'published_by', 'user');
select col_is_fk('event_attendee', 'event_id', 'event');
select col_is_fk('event_attendee', 'user_id', 'user');
select col_is_fk('event_category', 'community_id', 'community');
select col_is_fk('event_host', 'event_id', 'event');
select col_is_fk('event_host', 'user_id', 'user');
select col_is_fk('event_speaker', 'event_id', 'event');
select col_is_fk('event_speaker', 'user_id', 'user');
select col_is_fk('event_sponsor', 'event_id', 'event');
select col_is_fk('event_sponsor', 'group_sponsor_id', 'group_sponsor');
select col_is_fk('event_views', 'event_id', 'event');
select col_is_fk('event_waitlist', 'event_id', 'event');
select col_is_fk('event_waitlist', 'user_id', 'user');
select col_is_fk('group', 'community_id', 'community');
select col_is_fk('group', 'group_category_id', 'group_category');
select col_is_fk('group', 'group_site_layout_id', 'group_site_layout');
select col_is_fk('group', 'region_id', 'region');
select col_is_fk('group_category', 'community_id', 'community');
select col_is_fk('group_member', 'group_id', 'group');
select col_is_fk('group_member', 'user_id', 'user');
select col_is_fk('group_role_group_permission', 'group_permission_id', 'group_permission');
select col_is_fk('group_role_group_permission', 'group_role_id', 'group_role');
select col_is_fk('group_sponsor', 'group_id', 'group');
select col_is_fk('group_team', 'group_id', 'group');
select col_is_fk('group_team', 'role', 'group_role');
select col_is_fk('group_team', 'user_id', 'user');
select col_is_fk('group_views', 'group_id', 'group');
select col_is_fk('images', 'created_by', 'user');
select col_is_fk('legacy_event_host', 'event_id', 'event');
select col_is_fk('legacy_event_speaker', 'event_id', 'event');
select col_is_fk('meeting', 'auto_end_check_outcome', 'meeting_auto_end_check_outcome');
select col_is_fk('meeting', 'event_id', 'event');
select col_is_fk('meeting', 'meeting_provider_id', 'meeting_provider');
select col_is_fk('meeting', 'session_id', 'session');
select col_is_fk('notification', 'kind', 'notification_kind');
select col_is_fk('notification', 'notification_template_data_id', 'notification_template_data');
select col_is_fk('notification', 'user_id', 'user');
select col_is_fk('notification_attachment', 'attachment_id', 'attachment');
select col_is_fk('notification_attachment', 'notification_id', 'notification');
select col_is_fk('region', 'community_id', 'community');
select col_is_fk('session', 'event_id', 'event');
select col_is_fk('session', 'cfs_submission_id', 'cfs_submission');
select col_is_fk('session', 'meeting_provider_id', 'meeting_provider');
select col_is_fk('session', 'session_kind_id', 'session_kind');
select col_is_fk('session_proposal', 'co_speaker_user_id', 'user');
select col_is_fk('session_proposal', 'session_proposal_level_id', 'session_proposal_level');
select col_is_fk('session_proposal', 'session_proposal_status_id', 'session_proposal_status');
select col_is_fk('session_proposal', 'user_id', 'user');
select col_is_fk('session_speaker', 'session_id', 'session');
select col_is_fk('session_speaker', 'user_id', 'user');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
