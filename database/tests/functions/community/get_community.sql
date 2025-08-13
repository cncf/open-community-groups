-- Start transaction and plan tests
begin;
select plan(3);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'

-- Test 1: Community with all fields populated
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
    'A test community for testing purposes',
    'Test Community',
    'https://example.com/logo.png',
    'test.localhost',
    'test-community',
    '{"primary_color": "#FF0000"}'::jsonb,
    'Test Community Title',
    'https://example.com/banner.png',
    'https://example.com/banner-link',
    'Copyright © 2024 Test Community',
    '{"docs": "https://docs.example.com", "blog": "https://blog.example.com"}'::jsonb,
    'https://facebook.com/testcommunity',
    'https://flickr.com/testcommunity',
    'https://example.com/footer-logo.png',
    'https://github.com/testcommunity',
    'https://instagram.com/testcommunity',
    'https://linkedin.com/company/testcommunity',
    'To create a new group, please contact admin',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'https://testcommunity.slack.com',
    'https://twitter.com/testcommunity',
    'https://example.com',
    'https://wechat.com/testcommunity',
    'https://youtube.com/testcommunity'
);

select is(
    get_community('00000000-0000-0000-0000-000000000001'::uuid)::jsonb - 'community_id' - 'created_at',
    '{
        "active": true,
        "ad_banner_link_url": "https://example.com/banner-link",
        "ad_banner_url": "https://example.com/banner.png",
        "community_site_layout_id": "default",
        "copyright_notice": "Copyright © 2024 Test Community",
        "description": "A test community for testing purposes",
        "display_name": "Test Community",
        "extra_links": {"docs": "https://docs.example.com", "blog": "https://blog.example.com"},
        "facebook_url": "https://facebook.com/testcommunity",
        "flickr_url": "https://flickr.com/testcommunity",
        "footer_logo_url": "https://example.com/footer-logo.png",
        "github_url": "https://github.com/testcommunity",
        "header_logo_url": "https://example.com/logo.png",
        "host": "test.localhost",
        "instagram_url": "https://instagram.com/testcommunity",
        "linkedin_url": "https://linkedin.com/company/testcommunity",
        "name": "test-community",
        "new_group_details": "To create a new group, please contact admin",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "slack_url": "https://testcommunity.slack.com",
        "theme": {"primary_color": "#FF0000"},
        "title": "Test Community Title",
        "twitter_url": "https://twitter.com/testcommunity",
        "website_url": "https://example.com",
        "wechat_url": "https://wechat.com/testcommunity",
        "youtube_url": "https://youtube.com/testcommunity"
    }'::jsonb,
    'get_community should return correct data for community with all fields populated'
);

-- Test 2: Community with only required fields (optional fields NULL)
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community2ID',
    'minimal-community',
    'Minimal Community',
    'minimal.localhost',
    'Minimal Community Title',
    'A minimal test community',
    'https://minimal.com/logo.png',
    '{"primary_color": "#0000FF"}'::jsonb
);

select is(
    get_community('00000000-0000-0000-0000-000000000002'::uuid)::jsonb - 'community_id' - 'created_at',
    '{
        "active": true,
        "community_site_layout_id": "default",
        "description": "A minimal test community",
        "display_name": "Minimal Community",
        "header_logo_url": "https://minimal.com/logo.png",
        "host": "minimal.localhost",
        "name": "minimal-community",
        "theme": {"primary_color": "#0000FF"},
        "title": "Minimal Community Title"
    }'::jsonb,
    'get_community should return correct data for community with only required fields (NULL optional fields excluded)'
);

-- Test 3: Non-existent community
select is(
    get_community('00000000-0000-0000-0000-000000000099'::uuid)::jsonb,
    NULL,
    'get_community should return NULL for non-existent community'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;