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
    community_site_layout_id,
    description,
    display_name,
    header_logo_url,
    host,
    name,
    theme,
    title,
    ad_banner_url,
    ad_banner_link_url,
    copyright_notice,
    extra_links,
    facebook_url,
    favicon_url,
    flickr_url,
    footer_logo_url,
    github_url,
    instagram_url,
    jumbotron_image_url,
    linkedin_url,
    new_group_details,
    og_image_url,
    photos_urls,
    slack_url,
    twitter_url,
    website_url,
    wechat_url,
    youtube_url
) values (
    :'communityID',
    true,
    'default',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'Cloud Native Seattle',
    'https://original.com/header-logo.png',
    'seattle.cloudnative.org',
    'cloud-native-seattle',
    '{"primary_color": "#000000"}'::jsonb,
    'Cloud Native Seattle Community',
    'https://original.com/banner.png',
    'https://original.com/banner-link',
    'Copyright © 2024 Original',
    '{"docs": "https://docs.original.com"}'::jsonb,
    'https://facebook.com/original',
    'https://original.com/favicon.ico',
    'https://flickr.com/original',
    'https://original.com/footer-logo.png',
    'https://github.com/original',
    'https://instagram.com/original',
    'https://original.com/jumbotron.png',
    'https://linkedin.com/original',
    'Contact team members to create groups',
    'https://original.com/og.png',
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

-- updating required fields
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "active": false,
        "community_site_layout_id": "default",
        "description": "Updated description for Seattle cloud native community",
        "display_name": "Cloud Native Seattle Updated",
        "header_logo_url": "https://updated.com/header-logo.png",
        "host": "seattle.cloudnative.org",
        "name": "cloud-native-seattle-updated",
        "primary_color": "#FF0000",
        "title": "Cloud Native Seattle Updated"
    }'::jsonb
);

select is(
    (select get_community('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at'),
    '{
        "active": true,
        "ad_banner_link_url": "https://original.com/banner-link",
        "ad_banner_url": "https://original.com/banner.png",
        "community_site_layout_id": "default",
        "copyright_notice": "Copyright © 2024 Original",
        "description": "Updated description for Seattle cloud native community",
        "display_name": "Cloud Native Seattle Updated",
        "extra_links": {"docs": "https://docs.original.com"},
        "facebook_url": "https://facebook.com/original",
        "favicon_url": "https://original.com/favicon.ico",
        "flickr_url": "https://flickr.com/original",
        "footer_logo_url": "https://original.com/footer-logo.png",
        "github_url": "https://github.com/original",
        "header_logo_url": "https://updated.com/header-logo.png",
        "host": "seattle.cloudnative.org",
        "instagram_url": "https://instagram.com/original",
        "jumbotron_image_url": "https://original.com/jumbotron.png",
        "linkedin_url": "https://linkedin.com/original",
        "name": "cloud-native-seattle-updated",
        "new_group_details": "Contact team members to create groups",
        "og_image_url": "https://original.com/og.png",
        "photos_urls": ["https://original.com/photo1.jpg", "https://original.com/photo2.jpg"],
        "slack_url": "https://original.slack.com",
        "theme": {"primary_color": "#FF0000"},
        "title": "Cloud Native Seattle Updated",
        "twitter_url": "https://twitter.com/original",
        "website_url": "https://original.com",
        "wechat_url": "https://wechat.com/original",
        "youtube_url": "https://youtube.com/original"
    }'::jsonb,
    'update_community should update required fields correctly while preserving optional fields'
);

-- updating all fields including optional ones
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "active": true,
        "community_site_layout_id": "default",
        "description": "Comprehensive cloud native community in Seattle",
        "display_name": "Cloud Native Seattle Complete",
        "header_logo_url": "https://new.com/header.png",
        "host": "seattle.cloudnative.org",
        "name": "cloud-native-seattle-complete",
        "primary_color": "#00FF00",
        "title": "Cloud Native Seattle Complete",
        "ad_banner_url": "https://new.com/banner.png",
        "ad_banner_link_url": "https://new.com/link",
        "copyright_notice": "Copyright © 2025 New",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "favicon_url": "https://new.com/favicon.ico",
        "flickr_url": "https://flickr.com/new",
        "footer_logo_url": "https://new.com/footer.png",
        "github_url": "https://github.com/new",
        "instagram_url": "https://instagram.com/new",
        "jumbotron_image_url": "https://new.com/jumbotron.png",
        "linkedin_url": "https://linkedin.com/new",
        "new_group_details": "New groups welcome!",
        "og_image_url": "https://new.com/og.png",
        "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
        "slack_url": "https://new.slack.com",
        "twitter_url": "https://twitter.com/new",
        "website_url": "https://new.com",
        "wechat_url": "https://wechat.com/new",
        "youtube_url": "https://youtube.com/new",
        "jumbotron_image_url": "https://new.com/jumbotron.png"
    }'::jsonb
);

select is(
    (select get_community('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at'),
    '{
        "active": true,
        "ad_banner_link_url": "https://new.com/link",
        "ad_banner_url": "https://new.com/banner.png",
        "community_site_layout_id": "default",
        "copyright_notice": "Copyright © 2025 New",
        "description": "Comprehensive cloud native community in Seattle",
        "display_name": "Cloud Native Seattle Complete",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "favicon_url": "https://new.com/favicon.ico",
        "flickr_url": "https://flickr.com/new",
        "footer_logo_url": "https://new.com/footer.png",
        "github_url": "https://github.com/new",
        "header_logo_url": "https://new.com/header.png",
        "host": "seattle.cloudnative.org",
        "instagram_url": "https://instagram.com/new",
        "linkedin_url": "https://linkedin.com/new",
        "name": "cloud-native-seattle-complete",
        "new_group_details": "New groups welcome!",
        "og_image_url": "https://new.com/og.png",
        "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
        "slack_url": "https://new.slack.com",
        "theme": {"primary_color": "#00FF00"},
        "title": "Cloud Native Seattle Complete",
        "twitter_url": "https://twitter.com/new",
        "website_url": "https://new.com",
        "wechat_url": "https://wechat.com/new",
        "youtube_url": "https://youtube.com/new",
        "jumbotron_image_url": "https://new.com/jumbotron.png"
    }'::jsonb,
    'update_community should update all fields correctly including optional ones'
);

-- update_community converts empty strings to null for nullable fields
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "ad_banner_url": "",
        "ad_banner_link_url": "",
        "copyright_notice": "",
        "facebook_url": "",
        "favicon_url": "",
        "flickr_url": "",
        "footer_logo_url": "",
        "github_url": "",
        "instagram_url": "",
        "jumbotron_image_url": "",
        "linkedin_url": "",
        "new_group_details": "",
        "og_image_url": "",
        "slack_url": "",
        "twitter_url": "",
        "website_url": "",
        "wechat_url": "",
        "youtube_url": "",
        "jumbotron_image_url": ""
    }'::jsonb
);

select is(
    (select row_to_json(t.*)::jsonb - 'community_id' - 'created_at' - 'active' - 'community_site_layout_id' - 'description' - 'display_name' - 'header_logo_url' - 'host' - 'name' - 'theme' - 'title' - 'extra_links' - 'photos_urls'
     from (
        select * from community where community_id = '00000000-0000-0000-0000-000000000001'::uuid
     ) t),
    '{
        "ad_banner_url": null,
        "ad_banner_link_url": null,
        "copyright_notice": null,
        "facebook_url": null,
        "favicon_url": null,
        "flickr_url": null,
        "footer_logo_url": null,
        "github_url": null,
        "instagram_url": null,
        "jumbotron_image_url": null,
        "linkedin_url": null,
        "new_group_details": null,
        "og_image_url": null,
        "slack_url": null,
        "twitter_url": null,
        "website_url": null,
        "wechat_url": null,
        "youtube_url": null
    }'::jsonb,
    'update_community should convert empty strings to null for nullable fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
