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
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,

    ad_banner_link_url,
    ad_banner_url,
    og_image_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png',

    'https://example.com/ad-banner-link',
    'https://example.com/ad-banner.png',
    'https://example.com/community-og.png'
);

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
        "display_name": "Cloud Native Seattle",
        "logo_url": "https://example.com/logo.png",
        "name": "cloud-native-seattle",
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
