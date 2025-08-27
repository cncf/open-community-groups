-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(72);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Check expected extensions exist
select has_extension('pgcrypto');
select has_extension('postgis');

-- Check expected tables exist
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

-- Check tables have expected columns
select columns_are('community', array[
    'community_id',
    'active',
    'created_at',
    'description',
    'display_name',
    'header_logo_url',
    'host',
    'name',
    'theme',
    'title',
    'community_site_layout_id',
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

select columns_are('community_site_layout', array[
    'community_site_layout_id'
]);

select columns_are('community_team', array[
    'community_id',
    'user_id',
    'role',
    'created_at',
    'order'
]);

select columns_are('event', array[
    'event_id',
    'canceled',
    'created_at',
    'deleted',
    'description',
    'name',
    'published',
    'timezone',
    'tsdoc',
    'slug',
    'event_category_id',
    'event_kind_id',
    'group_id',
    'banner_url',
    'capacity',
    'deleted_at',
    'description_short',
    'ends_at',
    'logo_url',
    'meetup_url',
    'photos_urls',
    'published_at',
    'recording_url',
    'registration_required',
    'starts_at',
    'streaming_url',
    'tags',
    'timezone_abbr',
    'venue_address',
    'venue_city',
    'venue_name',
    'venue_zip_code',
    'published_by'
]);

select columns_are('event_attendee', array[
    'event_id',
    'user_id',
    'checked_in',
    'created_at'
]);

select columns_are('event_category', array[
    'event_category_id',
    'created_at',
    'name',
    'slug',
    'community_id',
    'order'
]);

select columns_are('event_host', array[
    'event_id',
    'user_id',
    'created_at'
]);

select columns_are('event_kind', array[
    'event_kind_id',
    'display_name'
]);

select columns_are('event_sponsor', array[
    'event_sponsor_id',
    'created_at',
    'level',
    'logo_url',
    'name',
    'event_id',
    'website_url'
]);

select columns_are('group', array[
    'group_id',
    'active',
    'created_at',
    'deleted',
    'name',
    'slug',
    'tsdoc',
    'community_id',
    'group_site_layout_id',
    'group_category_id',
    'description',
    'description_short',
    'banner_url',
    'city',
    'country_code',
    'country_name',
    'deleted_at',
    'extra_links',
    'facebook_url',
    'flickr_url',
    'github_url',
    'instagram_url',
    'linkedin_url',
    'location',
    'logo_url',
    'photos_urls',
    'slack_url',
    'state',
    'tags',
    'twitter_url',
    'website_url',
    'wechat_url',
    'youtube_url',
    'region_id'
]);

select columns_are('group_category', array[
    'group_category_id',
    'created_at',
    'name',
    'normalized_name',
    'order',
    'community_id'
]);

select columns_are('group_member', array[
    'group_id',
    'user_id',
    'created_at'
]);

select columns_are('group_site_layout', array[
    'group_site_layout_id'
]);

select columns_are('group_sponsor', array[
    'group_sponsor_id',
    'created_at',
    'level',
    'logo_url',
    'name',
    'group_id',
    'website_url'
]);

select columns_are('group_team', array[
    'group_id',
    'user_id',
    'role',
    'created_at',
    'order'
]);

select columns_are('region', array[
    'region_id',
    'created_at',
    'name',
    'normalized_name',
    'order',
    'community_id'
]);

select columns_are('user', array[
    'user_id',
    'auth_hash',
    'community_id',
    'created_at',
    'email',
    'email_verified',
    'name',
    'username',
    'bio',
    'city',
    'company',
    'country',
    'facebook_url',
    'interests',
    'linkedin_url',
    'password',
    'photo_url',
    'timezone',
    'title',
    'twitter_url',
    'website_url'
]);

-- Check tables have expected primary keys
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
select indexes_are('community', array[
    'community_pkey',
    'community_display_name_key',
    'community_host_key',
    'community_name_key',
    'community_community_site_layout_id_idx'
]);

select indexes_are('event', array[
    'event_pkey',
    'event_slug_group_id_key',
    'event_group_id_idx',
    'event_event_category_id_idx',
    'event_event_kind_id_idx',
    'event_published_by_idx',
    'event_tsdoc_idx'
]);

select indexes_are('group', array[
    'group_pkey',
    'group_slug_community_id_key',
    'group_community_id_idx',
    'group_group_category_id_idx',
    'group_region_id_idx',
    'group_group_site_layout_id_idx',
    'group_tsdoc_idx',
    'group_location_idx'
]);

select indexes_are('user', array[
    'user_pkey',
    'user_email_community_id_key',
    'user_username_community_id_key',
    'user_community_id_idx'
]);

-- Check expected functions exist
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

-- Check event kinds exist
select results_eq(
    'select * from event_kind order by event_kind_id',
    $$ values
        ('hybrid', 'Hybrid'),
        ('in-person', 'In Person'),
        ('virtual', 'Virtual')
    $$,
    'Event kinds should exist'
);

-- Check site layouts exist
select results_eq(
    'select * from community_site_layout',
    $$ values ('default') $$,
    'Community site layout should have default'
);

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
