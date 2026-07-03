-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '0c050000-0000-0000-0000-000000000001'
\set unknownAllianceID '0c050000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
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
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png',

    'https://example.com/ad-banner-link',
    'https://example.com/ad-banner.png',
    'https://example.com/alliance-og.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct alliance summary JSON
select is(
    get_alliance_summary(:'allianceID'::uuid)::jsonb,
    format('{
        "banner_mobile_url": "https://example.com/banner_mobile.png",
        "banner_url": "https://example.com/banner.png",
        "alliance_id": "%s",
        "coffee_meet_enabled": true,
        "display_name": "Cloud Native Seattle",
        "logo_url": "https://example.com/logo.png",
        "mentorship_enabled": true,
        "name": "cloud-native-seattle",
        "ad_banner_link_url": "https://example.com/ad-banner-link",
        "ad_banner_url": "https://example.com/ad-banner.png",
        "og_image_url": "https://example.com/alliance-og.png"
    }', :'allianceID')::jsonb,
    'Should return correct alliance summary data as JSON'
);

-- Should return null for non-existent alliance
select ok(
    get_alliance_summary(:'unknownAllianceID'::uuid) is null,
    'Should return null for non-existent alliance ID'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
