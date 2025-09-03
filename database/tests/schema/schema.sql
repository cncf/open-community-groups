-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(72);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: check expected extensions exist
select has_extension('pgcrypto');
select has_extension('postgis');

-- Test: check expected tables exist
select has_table('community');
select has_table('community_site_layout');
select has_table('community_team');
select has_table('event');
select has_table('event_attendee');
select has_table('event_category');
select has_table('event_host');
select has_table('event_kind');
select has_table('event_sponsor');
select has_table('group');
select has_table('group_category');
select has_table('group_member');
select has_table('group_site_layout');
select has_table('group_sponsor');
select has_table('group_team');
select has_table('region');
select has_table('user');

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
    'flickr_url',
    'footer_logo_url',
    'github_url',
    'instagram_url',
    'linkedin_url',
    'new_group_details',
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

    'banner_url',
    'capacity',
    'deleted_at',
    'description_short',
    'ends_at',
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
    'event_sponsor_id',
    'created_at',
    'event_id',
    'level',
    'logo_url',
    'name',

    'website_url'
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

-- Test: group_site_layout columns should match expected
select columns_are('group_site_layout', array[
    'group_site_layout_id'
]);

-- Test: group_sponsor columns should match expected
select columns_are('group_sponsor', array[
    'group_sponsor_id',
    'created_at',
    'group_id',
    'level',
    'logo_url',
    'name',

    'website_url'
]);

-- Test: group_team columns should match expected
select columns_are('group_team', array[
    'group_id',
    'user_id',
    'role',
    'created_at',

    'order'
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
select has_pk('community');
select has_pk('community_site_layout');
select has_pk('community_team');
select has_pk('event');
select has_pk('event_attendee');
select has_pk('event_category');
select has_pk('event_host');
select has_pk('event_kind');
select has_pk('event_sponsor');
select has_pk('group');
select has_pk('group_category');
select has_pk('group_member');
select has_pk('group_site_layout');
select has_pk('group_sponsor');
select has_pk('group_team');
select has_pk('region');
select has_pk('user');

-- Check tables have expected indexes
-- Test: community indexes should match expected
select indexes_are('community', array[
    'community_pkey',
    'community_display_name_key',
    'community_host_key',
    'community_name_key',
    'community_community_site_layout_id_idx'
]);

-- Test: event indexes should match expected
select indexes_are('event', array[
    'event_pkey',
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
    'group_slug_community_id_key',
    'group_community_id_idx',
    'group_group_category_id_idx',
    'group_region_id_idx',
    'group_group_site_layout_id_idx',
    'group_tsdoc_idx',
    'group_location_idx',
    'group_search_idx'
]);

-- Test: user indexes should match expected
select indexes_are('user', array[
    'user_pkey',
    'user_email_community_id_key',
    'user_username_community_id_key',
    'user_community_id_idx',
    'user_username_lower_idx',
    'user_name_lower_idx',
    'user_email_lower_idx'
]);

-- Test: check expected functions exist
select has_function('get_community');
select has_function('get_community_filters_options');
select has_function('get_community_home_stats');
select has_function('get_community_recently_added_groups');
select has_function('get_community_upcoming_events');
select has_function('search_community_events');
select has_function('search_community_groups');
select has_function('get_event');
select has_function('get_group');
select has_function('get_group_past_events');
select has_function('get_group_upcoming_events');
select has_function('i_array_to_string');

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
