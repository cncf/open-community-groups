-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c050000-0000-0000-0000-000000000001'
\set unknownCommunityID '0c050000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object(
    'ad_banner_link_url', 'https://example.com/ad-banner-link',
    'ad_banner_url', 'https://example.com/ad-banner.png',
    'banner_mobile_url', 'https://example.com/banner_mobile.png',
    'banner_url', 'https://example.com/banner.png',
    'display_name', 'Cloud Native Seattle Community Summary',
    'logo_url', 'https://example.com/logo.png',
    'name', 'cloud-native-seattle-community-summary',
    'og_image_url', 'https://example.com/community-og.png'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct community summary JSON
select is(
    get_community_summary(:'communityID'::uuid)::jsonb,
    format('{
        "banner_mobile_url": "https://example.com/banner_mobile.png",
        "banner_url": "https://example.com/banner.png",
        "community_id": "%s",
        "display_name": "Cloud Native Seattle Community Summary",
        "logo_url": "https://example.com/logo.png",
        "name": "cloud-native-seattle-community-summary",
        "ad_banner_link_url": "https://example.com/ad-banner-link",
        "ad_banner_url": "https://example.com/ad-banner.png",
        "og_image_url": "https://example.com/community-og.png"
    }', :'communityID')::jsonb,
    'Should return correct community summary data as JSON'
);

-- Should return null for non-existent community
select ok(
    get_community_summary(:'unknownCommunityID'::uuid) is null,
    'Should return null for non-existent community ID'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
