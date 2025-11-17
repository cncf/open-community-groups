-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(171);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check expected extensions exist
select has_extension('pgcrypto');
select has_extension('postgis');

-- Test: check expected tables exist
select has_table('attachment');
select has_table('community');
select has_table('community_site_layout');
select has_table('community_team');
select has_table('custom_notification');
select has_table('event');
select has_table('event_attendee');
select has_table('event_category');
select has_table('event_host');
select has_table('event_kind');
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
select has_table('notification_attachment');
select has_table('region');
select has_table('session');
select has_table('session_kind');
select has_table('session_speaker');
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

-- Test: community columns should match expected
select columns_are('community', array[
    'community_id',
    'active',
    'community_site_layout_id',
    'created_at',
    'description',
    'display_name',
    'header_logo_url',
    'host',
    'name',
    'theme',
    'title',

    'ad_banner_link_url',
    'ad_banner_url',
    'copyright_notice',
    'extra_links',
    'facebook_url',
    'favicon_url',
    'flickr_url',
    'footer_logo_url',
    'github_url',
    'instagram_url',
    'jumbotron_image_url',
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

    'banner_url',
    'capacity',
    'deleted_at',
    'description_short',
    'ends_at',
    'legacy_id',
    'logo_url',
    'meetup_url',
    'photos_urls',
    'published_at',
    'published_by',
    'recording_url',
    'registration_required',
    'starts_at',
    'streaming_url',
    'tags',
    'venue_address',
    'venue_city',
    'venue_name',
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

-- Test: event_sponsor columns should match expected
select columns_are('event_sponsor', array[
    'created_at',
    'event_id',
    'group_sponsor_id',
    'level'
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
    'recording_url',
    'streaming_url'
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

-- Test: notification_attachment columns should match expected
select columns_are('notification_attachment', array[
    'notification_id',
    'attachment_id'
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

-- Test: user columns should match expected
select columns_are('user', array[
    'user_id',
    'auth_hash',
    'community_id',
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
select has_pk('community');
select has_pk('community_site_layout');
select has_pk('community_team');
select has_pk('custom_notification');
select has_pk('event');
select has_pk('event_attendee');
select has_pk('event_category');
select has_pk('event_host');
select has_pk('event_kind');
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
select has_pk('notification_attachment');
select has_pk('region');
select has_pk('session');
select has_pk('session_kind');
select has_pk('session_speaker');
select has_pk('user');

-- Check tables have expected indexes
-- Test: attachment indexes should match expected
select indexes_are('attachment', array[
    'attachment_pkey',
    'attachment_hash_idx'
]);

-- Test: community indexes should match expected
select indexes_are('community', array[
    'community_pkey',
    'community_display_name_key',
    'community_host_key',
    'community_name_key',
    'community_community_site_layout_id_idx'
]);

-- Test: custom_notification indexes should match expected
select indexes_are('custom_notification', array[
    'custom_notification_created_by_idx',
    'custom_notification_event_id_idx',
    'custom_notification_group_id_idx',
    'custom_notification_pkey'
]);

-- Test: event indexes should match expected
select indexes_are('event', array[
    'event_pkey',
    'event_legacy_id_key',
    'event_slug_group_id_key',
    'event_group_id_idx',
    'event_event_category_id_idx',
    'event_event_kind_id_idx',
    'event_published_by_idx',
    'event_tsdoc_idx',
    'event_search_idx'
]);

-- Test: group indexes should match expected
select indexes_are('group', array[
    'group_pkey',
    'group_legacy_id_key',
    'group_slug_community_id_key',
    'group_community_id_idx',
    'group_group_category_id_idx',
    'group_region_id_idx',
    'group_group_site_layout_id_idx',
    'group_tsdoc_idx',
    'group_location_idx',
    'group_search_idx'
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

-- Test: notification_attachment indexes should match expected
select indexes_are('notification_attachment', array[
    'notification_attachment_pkey',
    'notification_attachment_attachment_id_idx'
]);

-- Test: session indexes should match expected
select indexes_are('session', array[
    'session_pkey',
    'session_event_id_idx',
    'session_session_kind_id_idx'
]);

-- Test: session_speaker indexes should match expected
select indexes_are('session_speaker', array[
    'session_speaker_pkey',
    'session_speaker_session_id_idx',
    'session_speaker_user_id_idx'
]);

-- Test: user indexes should match expected
select indexes_are('user', array[
    'user_pkey',
    'user_legacy_id_key',
    'user_email_community_id_key',
    'user_username_community_id_key',
    'user_community_id_idx',
    'user_username_lower_idx',
    'user_name_lower_idx',
    'user_email_lower_idx'
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
select has_function('get_community');
select has_function('get_community_filters_options');
select has_function('get_community_home_stats');
select has_function('get_community_recently_added_groups');
select has_function('get_community_upcoming_events');
select has_function('get_event_full');
select has_function('get_event_full_by_slug');
select has_function('get_event_summary');
select has_function('get_event_summary_by_id');
select has_function('get_group_full');
select has_function('get_group_full_by_slug');
select has_function('get_group_past_events');
select has_function('get_group_sponsor');
select has_function('get_group_summary');
select has_function('get_group_upcoming_events');
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
select has_function('list_regions');
select has_function('list_session_kinds');
select has_function('list_user_community_team_invitations');
select has_function('list_user_group_team_invitations');
select has_function('list_user_groups');
select has_function('publish_event');
select has_function('search_community_events');
select has_function('search_community_groups');
select has_function('search_event_attendees');
select has_function('search_user');
select has_function('sign_up_user');
select has_function('unpublish_event');
select has_function('update_community');
select has_function('update_event');
select has_function('update_group');
select has_function('update_group_sponsor');
select has_function('update_group_team_member_role');
select has_function('update_user_details');
select has_function('user_owns_community');
select has_function('user_owns_group');
select has_function('verify_email');

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
