-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(56);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check expected extensions exist
select has_extension('pgcrypto');
select has_extension('postgis');

-- Test: check expected tables exist
select has_table('attachment');
select has_table('auth_session');
select has_table('cfs_submission');
select has_table('cfs_submission_label');
select has_table('cfs_submission_rating');
select has_table('cfs_submission_status');
select has_table('community');
select has_table('community_permission');
select has_table('community_role');
select has_table('community_role_community_permission');
select has_table('community_role_group_permission');
select has_table('community_site_layout');
select has_table('community_team');
select has_table('community_views');
select has_table('custom_notification');
select has_table('email_verification_code');
select has_table('event');
select has_table('event_attendee');
select has_table('event_category');
select has_table('event_host');
select has_table('event_kind');
select has_table('event_cfs_label');
select has_table('event_speaker');
select has_table('event_sponsor');
select has_table('event_views');
select has_table('group');
select has_table('group_category');
select has_table('group_member');
select has_table('group_permission');
select has_table('group_role');
select has_table('group_role_group_permission');
select has_table('group_site_layout');
select has_table('group_sponsor');
select has_table('group_team');
select has_table('group_views');
select has_table('images');
select has_table('legacy_event_host');
select has_table('legacy_event_speaker');
select has_table('meeting');
select has_table('meeting_auto_end_check_outcome');
select has_table('meeting_provider');
select has_table('notification');
select has_table('notification_attachment');
select has_table('notification_kind');
select has_table('notification_template_data');
select has_table('region');
select has_table('session');
select has_table('session_kind');
select has_table('session_proposal');
select has_table('session_proposal_level');
select has_table('session_proposal_status');
select has_table('session_speaker');
select has_table('site');
select has_table('user');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
