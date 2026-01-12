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

-- Community with all fields
insert into community (
    community_id,
    active,
    community_site_layout_id,
    description,
    display_name,
    logo_url,
    name,
    ad_banner_url,
    ad_banner_link_url,
    banner_url,
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
    :'community1ID',
    true,
    'default',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'Cloud Native Seattle',
    'https://example.com/logo.png',
    'cloud-native-seattle',
    'https://example.com/banner.png',
    'https://example.com/banner-link',
    'https://example.com/community-banner.png',
    '{"docs": "https://docs.example.com", "blog": "https://blog.example.com"}'::jsonb,
    'https://facebook.com/testcommunity',
    'https://flickr.com/testcommunity',
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

-- Community with minimal fields
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_url
) values (
    :'community2ID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'A growing community for cloud native technologies in Portland',
    'https://portland.cloudnative.org/logo.png',
    'https://portland.cloudnative.org/banner.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct data for community with all fields populated
select is(
    get_community(:'community1ID'::uuid)::jsonb - 'community_id' - 'created_at',
    '{
        "active": true,
        "ad_banner_link_url": "https://example.com/banner-link",
        "ad_banner_url": "https://example.com/banner.png",
        "banner_url": "https://example.com/community-banner.png",
        "community_site_layout_id": "default",
        "description": "A vibrant community for cloud native technologies and practices in Seattle",
        "display_name": "Cloud Native Seattle",
        "extra_links": {"docs": "https://docs.example.com", "blog": "https://blog.example.com"},
        "facebook_url": "https://facebook.com/testcommunity",
        "flickr_url": "https://flickr.com/testcommunity",
        "github_url": "https://github.com/testcommunity",
        "instagram_url": "https://instagram.com/testcommunity",
        "linkedin_url": "https://linkedin.com/company/testcommunity",
        "logo_url": "https://example.com/logo.png",
        "name": "cloud-native-seattle",
        "new_group_details": "To create a new group, please contact team members",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "slack_url": "https://testcommunity.slack.com",
        "twitter_url": "https://twitter.com/testcommunity",
        "website_url": "https://example.com",
        "wechat_url": "https://wechat.com/testcommunity",
        "youtube_url": "https://youtube.com/testcommunity"
    }'::jsonb,
    'Should return correct data for community with all fields populated'
);

-- Should return correct data for community with only required fields
select is(
    get_community(:'community2ID'::uuid)::jsonb - 'community_id' - 'created_at',
    '{
        "active": true,
        "banner_url": "https://portland.cloudnative.org/banner.png",
        "community_site_layout_id": "default",
        "description": "A growing community for cloud native technologies in Portland",
        "display_name": "Cloud Native Portland",
        "logo_url": "https://portland.cloudnative.org/logo.png",
        "name": "cloud-native-portland"
    }'::jsonb,
    'Should return correct data for community with only required fields'
);

-- Should return null for non-existent ID
select ok(
    get_community(:'nonExistentCommunityID'::uuid) is null,
    'Should return null for non-existent ID'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
