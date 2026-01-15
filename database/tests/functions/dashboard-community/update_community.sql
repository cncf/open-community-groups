-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    community_site_layout_id,
    description,
    display_name,
    logo_url,
    name,
    ad_banner_url,
    ad_banner_link_url,
    extra_links,
    facebook_url,
    flickr_url,
    github_url,
    instagram_url,
    linkedin_url,
    new_group_details,
    photos_urls,
    slack_url,
    twitter_url,
    website_url,
    wechat_url,
    youtube_url
) values (
    :'communityID',
    true,
    'https://original.com/community-banner_mobile.png',
    'https://original.com/community-banner.png',
    'default',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'Cloud Native Seattle',
    'https://original.com/logo.png',
    'cloud-native-seattle',
    'https://original.com/banner.png',
    'https://original.com/banner-link',
    '{"docs": "https://docs.original.com"}'::jsonb,
    'https://facebook.com/original',
    'https://flickr.com/original',
    'https://github.com/original',
    'https://instagram.com/original',
    'https://linkedin.com/original',
    'Contact team members to create groups',
    array['https://original.com/photo1.jpg', 'https://original.com/photo2.jpg'],
    'https://original.slack.com',
    'https://twitter.com/original',
    'https://original.com',
    'https://wechat.com/original',
    'https://youtube.com/original'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update required fields and set optional fields to null when not provided
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "description": "Updated description for Seattle cloud native community",
        "display_name": "Cloud Native Seattle Updated",
        "logo_url": "https://updated.com/logo.png"
    }'::jsonb
);

select is(
    (select get_community_full('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at'),
    '{
        "active": true,
        "banner_mobile_url": "https://original.com/community-banner_mobile.png",
        "banner_url": "https://original.com/community-banner.png",
        "community_site_layout_id": "default",
        "description": "Updated description for Seattle cloud native community",
        "display_name": "Cloud Native Seattle Updated",
        "logo_url": "https://updated.com/logo.png",
        "name": "cloud-native-seattle"
    }'::jsonb,
    'Should update required fields and set optional fields to null when not provided'
);

-- Should update all fields including optional ones
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "description": "Comprehensive cloud native community in Seattle",
        "display_name": "Cloud Native Seattle Complete",
        "logo_url": "https://new.com/logo.png",
        "ad_banner_url": "https://new.com/banner.png",
        "ad_banner_link_url": "https://new.com/link",
        "banner_mobile_url": "https://new.com/community-banner_mobile.png",
        "banner_url": "https://new.com/community-banner.png",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "flickr_url": "https://flickr.com/new",
        "github_url": "https://github.com/new",
        "instagram_url": "https://instagram.com/new",
        "linkedin_url": "https://linkedin.com/new",
        "new_group_details": "New groups welcome!",
        "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
        "slack_url": "https://new.slack.com",
        "twitter_url": "https://twitter.com/new",
        "website_url": "https://new.com",
        "wechat_url": "https://wechat.com/new",
        "youtube_url": "https://youtube.com/new"
    }'::jsonb
);

select is(
    (select get_community_full('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at'),
    '{
        "active": true,
        "ad_banner_link_url": "https://new.com/link",
        "ad_banner_url": "https://new.com/banner.png",
        "banner_mobile_url": "https://new.com/community-banner_mobile.png",
        "banner_url": "https://new.com/community-banner.png",
        "community_site_layout_id": "default",
        "description": "Comprehensive cloud native community in Seattle",
        "display_name": "Cloud Native Seattle Complete",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "flickr_url": "https://flickr.com/new",
        "github_url": "https://github.com/new",
        "instagram_url": "https://instagram.com/new",
        "linkedin_url": "https://linkedin.com/new",
        "logo_url": "https://new.com/logo.png",
        "name": "cloud-native-seattle",
        "new_group_details": "New groups welcome!",
        "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
        "slack_url": "https://new.slack.com",
        "twitter_url": "https://twitter.com/new",
        "website_url": "https://new.com",
        "wechat_url": "https://wechat.com/new",
        "youtube_url": "https://youtube.com/new"
    }'::jsonb,
    'Should update all fields correctly including optional ones'
);

-- Should convert empty strings to null for nullable fields
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "ad_banner_url": "",
        "ad_banner_link_url": "",
        "facebook_url": "",
        "flickr_url": "",
        "github_url": "",
        "instagram_url": "",
        "linkedin_url": "",
        "new_group_details": "",
        "slack_url": "",
        "twitter_url": "",
        "website_url": "",
        "wechat_url": "",
        "youtube_url": ""
    }'::jsonb
);

select is(
    (select row_to_json(t.*)::jsonb - 'community_id' - 'created_at' - 'active' - 'banner_mobile_url' - 'banner_url' - 'community_site_layout_id' - 'description' - 'display_name' - 'logo_url' - 'name' - 'extra_links' - 'photos_urls'
     from (
        select * from community where community_id = '00000000-0000-0000-0000-000000000001'::uuid
     ) t),
    '{
        "ad_banner_url": null,
        "ad_banner_link_url": null,
        "facebook_url": null,
        "flickr_url": null,
        "github_url": null,
        "instagram_url": null,
        "linkedin_url": null,
        "new_group_details": null,
        "og_image_url": null,
        "slack_url": null,
        "twitter_url": null,
        "website_url": null,
        "wechat_url": null,
        "youtube_url": null
    }'::jsonb,
    'Should convert empty strings to null for nullable fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
