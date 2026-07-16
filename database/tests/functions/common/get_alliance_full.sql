-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '0c040000-0000-0000-0000-000000000001'
\set alliance2ID '0c040000-0000-0000-0000-000000000002'
\set nonExistentAllianceID '0c040000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance with all fields
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,

    active,
    ad_banner_link_url,
    ad_banner_url,
    bluesky_url,
    alliance_site_layout_id,
    extra_links,
    facebook_url,
    flickr_url,
    github_url,
    group_team_management_restricted,
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
    :'alliance1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png',

    true,
    'https://example.com/banner-link',
    'https://example.com/ad-banner.png',
    'https://bsky.app/profile/testalliance',
    'default',
    '{"docs": "https://docs.example.com", "blog": "https://blog.example.com"}'::jsonb,
    'https://facebook.com/testalliance',
    'https://flickr.com/testalliance',
    'https://github.com/testalliance',
    true,
    'https://instagram.com/testalliance',
    'https://linkedin.com/company/testalliance',
    'To create a new group, please contact team members',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'https://testalliance.slack.com',
    'https://twitter.com/testalliance',
    'https://example.com',
    'https://wechat.com/testalliance',
    'https://youtube.com/testalliance'
);

-- Alliance with minimal fields
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance2ID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'A growing alliance for cloud native technologies in Portland',
    'https://portland.cloudnative.org/banner_mobile.png',
    'https://portland.cloudnative.org/banner.png',
    'https://portland.cloudnative.org/logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct data for alliance with all fields populated
select is(
    get_alliance_full(:'alliance1ID'::uuid)::jsonb - 'alliance_id' - 'created_at',
    '{
        "active": true,
        "ad_banner_link_url": "https://example.com/banner-link",
        "ad_banner_url": "https://example.com/ad-banner.png",
        "banner_mobile_url": "https://example.com/banner_mobile.png",
        "banner_url": "https://example.com/banner.png",
        "bluesky_url": "https://bsky.app/profile/testalliance",
        "alliance_site_layout_id": "default",
        "book_exchange_enabled": false,
        "coffee_meet_enabled": true,
        "description": "A vibrant alliance for cloud native technologies and practices in Seattle",
        "display_name": "Cloud Native Seattle",
        "group_team_management_restricted": true,
        "extra_links": {"docs": "https://docs.example.com", "blog": "https://blog.example.com"},
        "facebook_url": "https://facebook.com/testalliance",
        "flickr_url": "https://flickr.com/testalliance",
        "github_url": "https://github.com/testalliance",
        "instagram_url": "https://instagram.com/testalliance",
        "linkedin_url": "https://linkedin.com/company/testalliance",
        "logo_url": "https://example.com/logo.png",
        "mentorship_enabled": true,
        "mock_interviews_enabled": true,
        "name": "cloud-native-seattle",
        "new_group_details": "To create a new group, please contact team members",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "report_public_enabled": false,
        "slack_url": "https://testalliance.slack.com",
        "twitter_url": "https://twitter.com/testalliance",
        "website_url": "https://example.com",
        "wechat_url": "https://wechat.com/testalliance",
        "youtube_url": "https://youtube.com/testalliance"
    }'::jsonb,
    'Should return correct data for alliance with all fields populated'
);

-- Should return correct data for alliance with only required fields
select is(
    get_alliance_full(:'alliance2ID'::uuid)::jsonb - 'alliance_id' - 'created_at',
    '{
        "active": true,
        "banner_mobile_url": "https://portland.cloudnative.org/banner_mobile.png",
        "banner_url": "https://portland.cloudnative.org/banner.png",
        "alliance_site_layout_id": "default",
        "book_exchange_enabled": false,
        "coffee_meet_enabled": true,
        "description": "A growing alliance for cloud native technologies in Portland",
        "display_name": "Cloud Native Portland",
        "group_team_management_restricted": false,
        "logo_url": "https://portland.cloudnative.org/logo.png",
        "mentorship_enabled": true,
        "mock_interviews_enabled": true,
        "name": "cloud-native-portland",
        "report_public_enabled": false
    }'::jsonb,
    'Should return correct data for alliance with only required fields'
);

-- Should return null for non-existent ID
select ok(
    get_alliance_full(:'nonExistentAllianceID'::uuid) is null,
    'Should return null for non-existent ID'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
