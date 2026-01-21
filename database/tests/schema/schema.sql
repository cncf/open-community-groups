-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(307);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check expected extensions exist
select has_extension('pgcrypto');
select has_extension('postgis');

-- Test: check expected tables exist
select has_table('attachment');
select has_table('auth_session');
select has_table('community');
select has_table('community_site_layout');
select has_table('community_team');
select has_table('custom_notification');
select has_table('email_verification_code');
select has_table('event');
select has_table('event_attendee');
select has_table('event_category');
select has_table('event_host');
select has_table('event_kind');
select has_table('event_speaker');
select has_table('event_sponsor');
select has_table('group');
select has_table('group_category');
select has_table('group_member');
select has_table('group_role');
select has_table('group_site_layout');
select has_table('group_sponsor');
select has_table('group_team');
select has_table('images');
select has_table('legacy_event_host');
select has_table('legacy_event_speaker');
select has_table('meeting');
select has_table('meeting_provider');
select has_table('notification');
select has_table('notification_attachment');
select has_table('notification_kind');
select has_table('notification_template_data');
select has_table('region');
select has_table('session');
select has_table('session_kind');
select has_table('session_speaker');
select has_table('site');
select has_table('user');

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

-- Test: community_team columns should match expected
select columns_are('community_team', array[
    'community_id',
    'accepted',
    'created_at',
    'user_id'
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
    'group_id',
    'name',
    'published',
    'slug',
    'timezone',
    'tsdoc',

    'banner_mobile_url',
    'banner_url',
    'capacity',
    'deleted_at',
    'description_short',
    'ends_at',
    'legacy_id',
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
    'venue_zip_code'
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
    'slug',

    'order'
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

-- Test: meeting columns should match expected
select columns_are('meeting', array[
    'meeting_id',
    'created_at',
    'join_url',
    'meeting_provider_id',
    'provider_meeting_id',

    'event_id',
    'password',
    'recording_url',
    'session_id',
    'updated_at'
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
    'timezone',
    'title',
    'twitter_url',
    'website_url'
]);

-- Test: check tables have expected primary keys
select has_pk('attachment');
select has_pk('auth_session');
select has_pk('community');
select has_pk('community_site_layout');
select has_pk('community_team');
select has_pk('custom_notification');
select has_pk('email_verification_code');
select has_pk('event');
select has_pk('event_attendee');
select has_pk('event_category');
select has_pk('event_host');
select has_pk('event_kind');
select has_pk('event_speaker');
select has_pk('event_sponsor');
select has_pk('group');
select has_pk('group_category');
select has_pk('group_member');
select has_pk('group_role');
select has_pk('group_site_layout');
select has_pk('group_sponsor');
select has_pk('group_team');
select has_pk('images');
select has_pk('legacy_event_host');
select has_pk('legacy_event_speaker');
select has_pk('meeting');
select has_pk('meeting_provider');
select has_pk('notification');
select has_pk('notification_attachment');
select has_pk('notification_kind');
select has_pk('notification_template_data');
select has_pk('region');
select has_pk('session');
select has_pk('session_kind');
select has_pk('session_speaker');
select has_pk('site');
select has_pk('user');

-- Test: check tables have expected foreign keys
select col_is_fk('community', 'community_site_layout_id', 'community_site_layout');
select col_is_fk('community_team', 'community_id', 'community');
select col_is_fk('community_team', 'user_id', 'user');
select col_is_fk('custom_notification', 'created_by', 'user');
select col_is_fk('custom_notification', 'event_id', 'event');
select col_is_fk('custom_notification', 'group_id', 'group');
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
select col_is_fk('group', 'community_id', 'community');
select col_is_fk('group', 'group_category_id', 'group_category');
select col_is_fk('group', 'group_site_layout_id', 'group_site_layout');
select col_is_fk('group', 'region_id', 'region');
select col_is_fk('group_category', 'community_id', 'community');
select col_is_fk('group_member', 'group_id', 'group');
select col_is_fk('group_member', 'user_id', 'user');
select col_is_fk('group_sponsor', 'group_id', 'group');
select col_is_fk('group_team', 'group_id', 'group');
select col_is_fk('group_team', 'role', 'group_role');
select col_is_fk('group_team', 'user_id', 'user');
select col_is_fk('images', 'created_by', 'user');
select col_is_fk('legacy_event_host', 'event_id', 'event');
select col_is_fk('legacy_event_speaker', 'event_id', 'event');
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
select col_is_fk('session', 'meeting_provider_id', 'meeting_provider');
select col_is_fk('session', 'session_kind_id', 'session_kind');
select col_is_fk('session_speaker', 'session_id', 'session');
select col_is_fk('session_speaker', 'user_id', 'user');

-- Test: attachment indexes should match expected
select indexes_are('attachment', array[
    'attachment_pkey',
    'attachment_hash_idx'
]);

-- Test: auth_session indexes should match expected
select indexes_are('auth_session', array[
    'auth_session_pkey'
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

-- Test: community_team indexes should match expected
select indexes_are('community_team', array[
    'community_team_pkey',
    'community_team_community_id_idx',
    'community_team_user_id_idx'
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
    'event_tsdoc_idx'
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
    'group_tsdoc_idx'
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

-- Test: group_team indexes should match expected
select indexes_are('group_team', array[
    'group_team_pkey',
    'group_team_group_id_idx',
    'group_team_user_id_idx',
    'group_team_role_idx'
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
    'meeting_pkey',
    'meeting_session_id_idx'
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
    'session_event_id_idx',
    'session_meeting_sync_idx',
    'session_session_kind_id_idx'
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

-- Test: check expected functions exist
select has_function('accept_community_team_invitation');
select has_function('accept_group_team_invitation');
select has_function('activate_group');
select has_function('add_community_team_member');
select has_function('add_event');
select has_function('add_group');
select has_function('add_group_sponsor');
select has_function('add_group_team_member');
select has_function('attend_event');
select has_function('cancel_event');
select has_function('check_in_event');
select has_function('delete_community_team_member');
select has_function('delete_event');
select has_function('delete_group');
select has_function('delete_group_sponsor');
select has_function('delete_group_team_member');
select has_function('generate_slug');
select has_function('get_community_full');
select has_function('get_community_id_by_name');
select has_function('get_community_name_by_id');
select has_function('get_community_recently_added_groups');
select has_function('get_community_site_stats');
select has_function('get_community_stats');
select has_function('get_community_upcoming_events');
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
select has_function('get_site_home_stats');
select has_function('get_site_recently_added_groups');
select has_function('get_site_settings');
select has_function('get_site_upcoming_events');
select has_function('get_user_by_id');
select has_function('i_array_to_string');
select has_function('is_event_attendee');
select has_function('is_group_member');
select has_function('join_group');
select has_function('leave_event');
select has_function('leave_group');
select has_function('list_community_team_members');
select has_function('list_event_attendees_ids');
select has_function('list_event_categories');
select has_function('list_event_kinds');
select has_function('list_group_categories');
select has_function('list_group_events');
select has_function('list_group_members');
select has_function('list_group_members_ids');
select has_function('list_group_roles');
select has_function('list_group_sponsors');
select has_function('list_group_team_members');
select has_function('list_communities');
select has_function('list_regions');
select has_function('list_session_kinds');
select has_function('list_user_community_team_invitations');
select has_function('list_user_group_team_invitations');
select has_function('list_user_groups');
select has_function('publish_event');
select has_function('search_event_attendees');
select has_function('search_events');
select has_function('search_groups');
select has_function('search_user');
select has_function('sign_up_user');
select has_function('unpublish_event');
select has_function('update_community');
select has_function('update_event');
select has_function('update_group');
select has_function('update_group_sponsor');
select has_function('update_group_team_member_role');
select has_function('update_meeting_recording_url');
select has_function('update_user_details');
select has_function('user_owns_community');
select has_function('user_owns_group');
select has_function('user_owns_groups_in_community');
select has_function('verify_email');

-- Test: check expected trigger functions exist
select has_function('check_event_category_community');
select has_function('check_event_sponsor_group');
select has_function('check_group_category_community');
select has_function('check_group_region_community');
select has_function('check_session_within_event_bounds');

-- Test: check expected triggers exist
select has_trigger('event', 'event_category_community_check');
select has_trigger('event_sponsor', 'event_sponsor_group_check');
select has_trigger('group', 'group_category_community_check');
select has_trigger('group', 'group_region_community_check');
select has_trigger('session', 'session_within_event_bounds_check');

-- Test: custom_notification table expected constraints exist
select has_check('custom_notification');

-- Test: event table expected constraints exist
select has_check('event', 'event_check');
select has_check('event', 'event_check1');
select has_check('event', 'event_check2');
select has_check('event', 'event_meeting_capacity_required_chk');
select has_check('event', 'event_meeting_conflict_chk');
select has_check('event', 'event_meeting_kind_chk');
select has_check('event', 'event_meeting_provider_required_chk');
select has_check('event', 'event_meeting_requested_times_chk');

-- Test: group table expected constraints exist
select has_check('group', 'group_check');

-- Test: session table expected constraints exist
select has_check('session', 'session_check');
select has_check('session', 'session_meeting_conflict_chk');
select has_check('session', 'session_meeting_provider_required_chk');
select has_check('session', 'session_meeting_requested_times_chk');

-- Test: event kinds should match expected values
select results_eq(
    'select * from event_kind order by event_kind_id',
    $$ values
        ('hybrid', 'Hybrid'),
        ('in-person', 'In Person'),
        ('virtual', 'Virtual')
    $$,
    'Event kinds should exist'
);

-- Test: meeting providers should match expected values
select results_eq(
    'select * from meeting_provider order by meeting_provider_id',
    $$ values
        ('zoom', 'Zoom')
    $$,
    'Meeting providers should exist'
);

-- Test: notification kinds should match expected values
select results_eq(
    'select name from notification_kind order by name',
    $$ values
        ('community-team-invitation'),
        ('email-verification'),
        ('event-canceled'),
        ('event-custom'),
        ('event-published'),
        ('event-rescheduled'),
        ('event-welcome'),
        ('group-custom'),
        ('group-team-invitation'),
        ('group-welcome'),
        ('speaker-welcome')
    $$,
    'Notification kinds should exist'
);

-- Test: session kinds should match expected values
select results_eq(
    'select * from session_kind order by session_kind_id',
    $$ values
        ('hybrid', 'Hybrid'),
        ('in-person', 'In-Person'),
        ('virtual', 'Virtual')
    $$,
    'Session kinds should exist'
);

-- Test: community site layout should match expected
select results_eq(
    'select * from community_site_layout',
    $$ values ('default') $$,
    'Community site layout should have default'
);

-- Test: group role should match expected values
select results_eq(
    'select * from group_role order by group_role_id',
    $$ values
        ('organizer', 'Organizer')
    $$,
    'Group roles should exist'
);

-- Test: group site layout should match expected
select results_eq(
    'select * from group_site_layout',
    $$ values ('default') $$,
    'Group site layout should have default'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
