-- Start transaction and plan tests
begin;
select plan(3);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'

-- Seed community with all fields
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
    flickr_url,
    footer_logo_url,
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
    :'community1ID',
    true,
    'default',
    'Original description',
    'Original Display Name',
    'https://original.com/header-logo.png',
    'original.example.com',
    'original-name',
    '{"primary_color": "#000000"}'::jsonb,
    'Original Title',
    'https://original.com/banner.png',
    'https://original.com/banner-link',
    'Copyright © 2024 Original',
    '{"docs": "https://docs.original.com"}'::jsonb,
    'https://facebook.com/original',
    'https://flickr.com/original',
    'https://original.com/footer-logo.png',
    'https://github.com/original',
    'https://instagram.com/original',
    'https://linkedin.com/original',
    'Contact admin to create groups',
    array['https://original.com/photo1.jpg', 'https://original.com/photo2.jpg'],
    'https://original.slack.com',
    'https://twitter.com/original',
    'https://original.com',
    'https://wechat.com/original',
    'https://youtube.com/original'
);

-- Test updating required fields
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "active": false,
        "community_site_layout_id": "default",
        "description": "Updated description",
        "display_name": "Updated Display Name",
        "header_logo_url": "https://updated.com/header-logo.png",
        "host": "updated.example.com",
        "name": "updated-name",
        "primary_color": "#FF0000",
        "title": "Updated Title"
    }'::jsonb
);

select is(
    (select get_community('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at'),
    '{
        "active": false,
        "ad_banner_link_url": "https://original.com/banner-link",
        "ad_banner_url": "https://original.com/banner.png",
        "community_site_layout_id": "default",
        "copyright_notice": "Copyright © 2024 Original",
        "description": "Updated description",
        "display_name": "Updated Display Name",
        "extra_links": {"docs": "https://docs.original.com"},
        "facebook_url": "https://facebook.com/original",
        "flickr_url": "https://flickr.com/original",
        "footer_logo_url": "https://original.com/footer-logo.png",
        "github_url": "https://github.com/original",
        "header_logo_url": "https://updated.com/header-logo.png",
        "host": "updated.example.com",
        "instagram_url": "https://instagram.com/original",
        "linkedin_url": "https://linkedin.com/original",
        "name": "updated-name",
        "new_group_details": "Contact admin to create groups",
        "photos_urls": ["https://original.com/photo1.jpg", "https://original.com/photo2.jpg"],
        "slack_url": "https://original.slack.com",
        "theme": {"primary_color": "#FF0000"},
        "title": "Updated Title",
        "twitter_url": "https://twitter.com/original",
        "website_url": "https://original.com",
        "wechat_url": "https://wechat.com/original",
        "youtube_url": "https://youtube.com/original"
    }'::jsonb,
    'update_community should update required fields correctly while preserving optional fields'
);

-- Test updating all fields including optional ones
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "active": true,
        "community_site_layout_id": "default",
        "description": "Fully updated description",
        "display_name": "Fully Updated Display",
        "header_logo_url": "https://new.com/header.png",
        "host": "new.example.com",
        "name": "new-name",
        "primary_color": "#00FF00",
        "title": "Fully Updated Title",
        "ad_banner_url": "https://new.com/banner.png",
        "ad_banner_link_url": "https://new.com/link",
        "copyright_notice": "Copyright © 2025 New",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "flickr_url": "https://flickr.com/new",
        "footer_logo_url": "https://new.com/footer.png",
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
    (select get_community('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at'),
    '{
        "active": true,
        "ad_banner_link_url": "https://new.com/link",
        "ad_banner_url": "https://new.com/banner.png",
        "community_site_layout_id": "default",
        "copyright_notice": "Copyright © 2025 New",
        "description": "Fully updated description",
        "display_name": "Fully Updated Display",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "flickr_url": "https://flickr.com/new",
        "footer_logo_url": "https://new.com/footer.png",
        "github_url": "https://github.com/new",
        "header_logo_url": "https://new.com/header.png",
        "host": "new.example.com",
        "instagram_url": "https://instagram.com/new",
        "linkedin_url": "https://linkedin.com/new",
        "name": "new-name",
        "new_group_details": "New groups welcome!",
        "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
        "slack_url": "https://new.slack.com",
        "theme": {"primary_color": "#00FF00"},
        "title": "Fully Updated Title",
        "twitter_url": "https://twitter.com/new",
        "website_url": "https://new.com",
        "wechat_url": "https://wechat.com/new",
        "youtube_url": "https://youtube.com/new"
    }'::jsonb,
    'update_community should update all fields correctly including optional ones'
);

-- Test update_community converts empty strings to null for nullable fields
select update_community(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '{
        "ad_banner_url": "",
        "ad_banner_link_url": "",
        "copyright_notice": "",
        "facebook_url": "",
        "flickr_url": "",
        "footer_logo_url": "",
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
    (select row_to_json(t.*)::jsonb - 'community_id' - 'created_at' - 'active' - 'community_site_layout_id' - 'description' - 'display_name' - 'header_logo_url' - 'host' - 'name' - 'theme' - 'title' - 'extra_links' - 'photos_urls'
     from (
        select * from community where community_id = '00000000-0000-0000-0000-000000000001'::uuid
     ) t),
    '{
        "ad_banner_url": null,
        "ad_banner_link_url": null,
        "copyright_notice": null,
        "facebook_url": null,
        "flickr_url": null,
        "footer_logo_url": null,
        "github_url": null,
        "instagram_url": null,
        "linkedin_url": null,
        "new_group_details": null,
        "slack_url": null,
        "twitter_url": null,
        "website_url": null,
        "wechat_url": null,
        "youtube_url": null
    }'::jsonb,
    'update_community should convert empty strings to null for nullable fields'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;