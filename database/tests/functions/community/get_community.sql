-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set nonExistentCommunityID '00000000-0000-0000-0000-000000000099'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (with all fields populated)
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
    'A vibrant community for cloud native technologies and practices in Seattle',
    'Cloud Native Seattle',
    'https://example.com/logo.png',
    'seattle.cloudnative.org',
    'cloud-native-seattle',
    '{"primary_color": "#FF0000"}'::jsonb,
    'Cloud Native Seattle Community',
    'https://example.com/banner.png',
    'https://example.com/banner-link',
    'Copyright © 2024 Cloud Native Seattle',
    '{"docs": "https://docs.example.com", "blog": "https://blog.example.com"}'::jsonb,
    'https://facebook.com/testcommunity',
    'https://flickr.com/testcommunity',
    'https://example.com/footer-logo.png',
    'https://github.com/testcommunity',
    'https://instagram.com/testcommunity',
    'https://linkedin.com/company/testcommunity',
    'To create a new group, please contact team members',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'https://testcommunity.slack.com',
    'https://twitter.com/testcommunity',
    'https://example.com',
    'https://wechat.com/testcommunity',
    'https://youtube.com/testcommunity'
);

-- Community (with only required fields)
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
    'cloud-native-portland',
    'Cloud Native Portland',
    'portland.cloudnative.org',
    'Cloud Native Portland Community',
    'A growing community for cloud native technologies in Portland',
    'https://portland.cloudnative.org/logo.png',
    '{"primary_color": "#0000FF"}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Function returns correct data for community with all fields
select is(
    get_community(:'community1ID'::uuid)::jsonb - 'community_id' - 'created_at',
    '{
        "active": true,
        "ad_banner_link_url": "https://example.com/banner-link",
        "ad_banner_url": "https://example.com/banner.png",
        "community_site_layout_id": "default",
        "copyright_notice": "Copyright © 2024 Cloud Native Seattle",
        "description": "A vibrant community for cloud native technologies and practices in Seattle",
        "display_name": "Cloud Native Seattle",
        "extra_links": {"docs": "https://docs.example.com", "blog": "https://blog.example.com"},
        "facebook_url": "https://facebook.com/testcommunity",
        "flickr_url": "https://flickr.com/testcommunity",
        "footer_logo_url": "https://example.com/footer-logo.png",
        "github_url": "https://github.com/testcommunity",
        "header_logo_url": "https://example.com/logo.png",
        "host": "seattle.cloudnative.org",
        "instagram_url": "https://instagram.com/testcommunity",
        "linkedin_url": "https://linkedin.com/company/testcommunity",
        "name": "cloud-native-seattle",
        "new_group_details": "To create a new group, please contact team members",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "slack_url": "https://testcommunity.slack.com",
        "theme": {"primary_color": "#FF0000"},
        "title": "Cloud Native Seattle Community",
        "twitter_url": "https://twitter.com/testcommunity",
        "website_url": "https://example.com",
        "wechat_url": "https://wechat.com/testcommunity",
        "youtube_url": "https://youtube.com/testcommunity"
    }'::jsonb,
    'get_community should return correct data for community with all fields populated'
);

-- Function returns correct data for community with minimal fields
select is(
    get_community(:'community2ID'::uuid)::jsonb - 'community_id' - 'created_at',
    '{
        "active": true,
        "community_site_layout_id": "default",
        "description": "A growing community for cloud native technologies in Portland",
        "display_name": "Cloud Native Portland",
        "header_logo_url": "https://portland.cloudnative.org/logo.png",
        "host": "portland.cloudnative.org",
        "name": "cloud-native-portland",
        "theme": {"primary_color": "#0000FF"},
        "title": "Cloud Native Portland Community"
    }'::jsonb,
    'get_community should return correct data for community with only required fields (NULL optional fields excluded)'
);

-- Function returns null for non-existent community
select is(
    get_community(:'nonExistentCommunityID'::uuid)::jsonb,
    NULL,
    'get_community should return NULL for non-existent community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
