-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(55);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: attachment columns should match expected
select columns_are('attachment', array[
    'attachment_id',
    'content_type',
    'created_at',
    'data',
    'file_name',
    'hash'
]);

-- Test: auth_session columns should match expected
select columns_are('auth_session', array[
    'auth_session_id',
    'data',
    'expires_at'
]);

-- Test: cfs_submission columns should match expected
select columns_are('cfs_submission', array[
    'cfs_submission_id',
    'created_at',
    'event_id',
    'session_proposal_id',
    'status_id',

    'action_required_message',
    'reviewed_by',
    'updated_at'
]);

-- Test: cfs_submission_label columns should match expected
select columns_are('cfs_submission_label', array[
    'cfs_submission_id',
    'created_at',
    'event_cfs_label_id'
]);

-- Test: cfs_submission_rating columns should match expected
select columns_are('cfs_submission_rating', array[
    'cfs_submission_id',
    'reviewer_id',
    'stars',

    'comments',
    'created_at',
    'updated_at'
]);

-- Test: cfs_submission_status columns should match expected
select columns_are('cfs_submission_status', array[
    'cfs_submission_status_id',
    'display_name'
]);

-- Test: community columns should match expected
select columns_are('community', array[
    'community_id',
    'active',
    'banner_mobile_url',
    'banner_url',
    'community_site_layout_id',
    'created_at',
    'description',
    'display_name',
    'logo_url',
    'name',

    'ad_banner_link_url',
    'ad_banner_url',
    'bluesky_url',
    'extra_links',
    'facebook_url',
    'flickr_url',
    'github_url',
    'instagram_url',
    'linkedin_url',
    'new_group_details',
    'og_image_url',
    'photos_urls',
    'slack_url',
    'twitter_url',
    'website_url',
    'wechat_url',
    'youtube_url'
]);

-- Test: community_site_layout columns should match expected
select columns_are('community_site_layout', array[
    'community_site_layout_id'
]);

-- Test: community_role columns should match expected
select columns_are('community_role', array[
    'community_role_id',
    'display_name'
]);

-- Test: community_permission columns should match expected
select columns_are('community_permission', array[
    'community_permission_id',
    'display_name'
]);

-- Test: community_role_community_permission columns should match expected
select columns_are('community_role_community_permission', array[
    'community_permission_id',
    'community_role_id'
]);

-- Test: community_role_group_permission columns should match expected
select columns_are('community_role_group_permission', array[
    'community_role_id',
    'group_permission_id'
]);

-- Test: community_team columns should match expected
select columns_are('community_team', array[
    'community_id',
    'accepted',
    'created_at',
    'role',
    'user_id'
]);

-- Test: community_views columns should match expected
select columns_are('community_views', array[
    'community_id',
    'day',
    'total'
]);

-- Test: custom_notification columns should match expected
select columns_are('custom_notification', array[
    'custom_notification_id',
    'created_at',
    'created_by',
    'event_id',
    'group_id',
    'subject',
    'body'
]);

-- Test: email_verification_code columns should match expected
select columns_are('email_verification_code', array[
    'email_verification_code_id',
    'created_at',
    'user_id'
]);

-- Test: event columns should match expected
select columns_are('event', array[
    'event_id',
    'canceled',
    'created_at',
    'deleted',
    'description',
    'event_category_id',
    'event_kind_id',
    'event_reminder_enabled',
    'group_id',
    'name',
    'published',
    'slug',
    'timezone',
    'tsdoc',

    'banner_mobile_url',
    'banner_url',
    'capacity',
    'cfs_description',
    'cfs_enabled',
    'cfs_ends_at',
    'cfs_starts_at',
    'deleted_at',
    'description_short',
    'ends_at',
    'event_reminder_evaluated_for_starts_at',
    'event_reminder_sent_at',
    'legacy_id',
    'legacy_url',
    'location',
    'logo_url',
    'meeting_error',
    'meeting_hosts',
    'meeting_in_sync',
    'meeting_join_url',
    'meeting_provider_id',
    'meeting_recording_url',
    'meeting_requested',
    'meetup_url',
    'photos_urls',
    'published_at',
    'published_by',
    'registration_required',
    'starts_at',
    'tags',
    'venue_address',
    'venue_city',
    'venue_country_code',
    'venue_country_name',
    'venue_name',
    'venue_state',
    'venue_zip_code',
    'waitlist_enabled'
]);

-- Test: event_attendee columns should match expected
select columns_are('event_attendee', array[
    'event_id',
    'user_id',
    'checked_in',
    'checked_in_at',
    'created_at'
]);

-- Test: event_category columns should match expected
select columns_are('event_category', array[
    'event_category_id',
    'community_id',
    'created_at',
    'name',
    'order',
    'slug'
]);

-- Test: event_host columns should match expected
select columns_are('event_host', array[
    'event_id',
    'user_id',
    'created_at'
]);

-- Test: event_kind columns should match expected
select columns_are('event_kind', array[
    'event_kind_id',
    'display_name'
]);

-- Test: event_cfs_label columns should match expected
select columns_are('event_cfs_label', array[
    'color',
    'created_at',
    'event_id',
    'event_cfs_label_id',
    'name'
]);

-- Test: event_speaker columns should match expected
select columns_are('event_speaker', array[
    'created_at',
    'event_id',
    'featured',
    'user_id'
]);

-- Test: event_sponsor columns should match expected
select columns_are('event_sponsor', array[
    'created_at',
    'event_id',
    'group_sponsor_id',
    'level'
]);

-- Test: event_views columns should match expected
select columns_are('event_views', array[
    'event_id',
    'day',
    'total'
]);

-- Test: event_waitlist columns should match expected
select columns_are('event_waitlist', array[
    'event_id',
    'user_id',
    'created_at'
]);

-- Test: meeting columns should match expected
select columns_are('meeting', array[
    'meeting_id',
    'created_at',
    'join_url',
    'meeting_provider_id',
    'provider_meeting_id',

    'auto_end_check_at',
    'auto_end_check_outcome',
    'event_id',
    'password',
    'provider_host_user_id',
    'recording_url',
    'session_id',
    'updated_at'
]);

-- Test: meeting_auto_end_check_outcome columns should match expected
select columns_are('meeting_auto_end_check_outcome', array[
    'meeting_auto_end_check_outcome_id',
    'display_name'
]);

-- Test: meeting_provider columns should match expected
select columns_are('meeting_provider', array[
    'meeting_provider_id',
    'display_name'
]);

-- Test: group columns should match expected
select columns_are('group', array[
    'group_id',
    'active',
    'community_id',
    'created_at',
    'deleted',
    'group_category_id',
    'group_site_layout_id',
    'name',
    'slug',
    'tsdoc',

    'banner_mobile_url',
    'banner_url',
    'bluesky_url',
    'city',
    'country_code',
    'country_name',
    'deleted_at',
    'description',
    'description_short',
    'extra_links',
    'facebook_url',
    'flickr_url',
    'github_url',
    'instagram_url',
    'legacy_id',
    'legacy_url',
    'linkedin_url',
    'location',
    'logo_url',
    'photos_urls',
    'region_id',
    'slack_url',
    'state',
    'tags',
    'twitter_url',
    'website_url',
    'wechat_url',
    'youtube_url'
]);

-- Test: group_category columns should match expected
select columns_are('group_category', array[
    'group_category_id',
    'community_id',
    'created_at',
    'name',
    'normalized_name',

    'order'
]);

-- Test: group_member columns should match expected
select columns_are('group_member', array[
    'group_id',
    'user_id',
    'created_at'
]);

-- Test: group_role columns should match expected
select columns_are('group_role', array[
    'group_role_id',
    'display_name'
]);

-- Test: group_permission columns should match expected
select columns_are('group_permission', array[
    'group_permission_id',
    'display_name'
]);

-- Test: group_role_group_permission columns should match expected
select columns_are('group_role_group_permission', array[
    'group_permission_id',
    'group_role_id'
]);

-- Test: group_site_layout columns should match expected
select columns_are('group_site_layout', array[
    'group_site_layout_id'
]);

-- Test: group_sponsor columns should match expected
select columns_are('group_sponsor', array[
    'group_sponsor_id',
    'created_at',
    'group_id',
    'logo_url',
    'name',

    'website_url'
]);

-- Test: group_team columns should match expected
select columns_are('group_team', array[
    'group_id',
    'user_id',
    'accepted',
    'created_at',
    'role',

    'order'
]);

-- Test: group_views columns should match expected
select columns_are('group_views', array[
    'group_id',
    'day',
    'total'
]);

-- Test: images columns should match expected
select columns_are('images', array[
    'file_name',
    'content_type',
    'created_at',
    'created_by',
    'data'
]);

-- Test: session columns should match expected
select columns_are('session', array[
    'session_id',
    'created_at',
    'event_id',
    'name',
    'session_kind_id',
    'starts_at',

    'cfs_submission_id',
    'description',
    'ends_at',
    'location',
    'meeting_error',
    'meeting_hosts',
    'meeting_in_sync',
    'meeting_join_url',
    'meeting_provider_id',
    'meeting_recording_url',
    'meeting_requested'
]);

-- Test: session_kind columns should match expected
select columns_are('session_kind', array[
    'session_kind_id',
    'display_name'
]);

-- Test: session_proposal columns should match expected
select columns_are('session_proposal', array[
    'created_at',
    'description',
    'duration',
    'session_proposal_id',
    'session_proposal_level_id',
    'title',
    'user_id',

    'co_speaker_user_id',
    'session_proposal_status_id',
    'updated_at'
]);

-- Test: session_proposal_level columns should match expected
select columns_are('session_proposal_level', array[
    'session_proposal_level_id',
    'display_name'
]);

-- Test: session_proposal_status columns should match expected
select columns_are('session_proposal_status', array[
    'session_proposal_status_id',
    'display_name'
]);

-- Test: session_speaker columns should match expected
select columns_are('session_speaker', array[
    'created_at',
    'featured',
    'session_id',
    'user_id'
]);

-- Test: legacy_event_host columns should match expected
select columns_are('legacy_event_host', array[
    'legacy_event_host_id',
    'event_id',

    'bio',
    'name',
    'photo_url',
    'title'
]);

-- Test: legacy_event_speaker columns should match expected
select columns_are('legacy_event_speaker', array[
    'legacy_event_speaker_id',
    'event_id',

    'bio',
    'name',
    'photo_url',
    'title'
]);

-- Test: notification columns should match expected
select columns_are('notification', array[
    'notification_id',
    'created_at',
    'kind',
    'processed',
    'user_id',

    'error',
    'notification_template_data_id',
    'processed_at'
]);

-- Test: notification_attachment columns should match expected
select columns_are('notification_attachment', array[
    'notification_id',
    'attachment_id'
]);

-- Test: notification_kind columns should match expected
select columns_are('notification_kind', array[
    'notification_kind_id',

    'name'
]);

-- Test: notification_template_data columns should match expected
select columns_are('notification_template_data', array[
    'notification_template_data_id',
    'created_at',
    'data',
    'hash'
]);

-- Test: region columns should match expected
select columns_are('region', array[
    'region_id',
    'community_id',
    'created_at',
    'name',
    'normalized_name',

    'order'
]);

-- Test: site columns should match expected
select columns_are('site', array[
    'site_id',
    'created_at',
    'description',
    'theme',
    'title',

    'copyright_notice',
    'favicon_url',
    'footer_logo_url',
    'header_logo_url',
    'og_image_url'
]);

-- Test: user columns should match expected
select columns_are('user', array[
    'user_id',
    'auth_hash',
    'created_at',
    'email',
    'email_verified',
    'username',

    'bio',
    'bluesky_url',
    'city',
    'company',
    'country',
    'facebook_url',
    'interests',
    'legacy_id',
    'linkedin_url',
    'name',
    'password',
    'photo_url',
    'provider',
    'timezone',
    'title',
    'twitter_url',
    'website_url'
]);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
