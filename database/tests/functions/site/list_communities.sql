-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityActiveAlphaID '9a070000-0000-0000-0000-000000000001'
\set communityActiveBetaID '9a070000-0000-0000-0000-000000000002'
\set communityInactiveID '9a070000-0000-0000-0000-000000000003'
\set communityNoGroupsID '9a070000-0000-0000-0000-000000000004'
\set communityOnlyDeletedGroupID '9a070000-0000-0000-0000-000000000005'
\set communityOnlyInactiveGroupID '9a070000-0000-0000-0000-000000000006'
\set groupActiveAlphaID '9a070000-0000-0000-0000-000000000007'
\set groupActiveBetaID '9a070000-0000-0000-0000-000000000008'
\set groupCategoryActiveAlphaID '9a070000-0000-0000-0000-000000000009'
\set groupCategoryActiveBetaID '9a070000-0000-0000-0000-000000000010'
\set groupCategoryInactiveCommunityID '9a070000-0000-0000-0000-000000000011'
\set groupCategoryOnlyDeletedID '9a070000-0000-0000-0000-000000000012'
\set groupCategoryOnlyInactiveID '9a070000-0000-0000-0000-000000000013'
\set groupInactiveCommunityID '9a070000-0000-0000-0000-000000000014'
\set groupOnlyDeletedID '9a070000-0000-0000-0000-000000000015'
\set groupOnlyInactiveID '9a070000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities covering active, inactive, and group eligibility scenarios
select fx_community(:'communityActiveAlphaID', jsonb_build_object(
    'banner_mobile_url', 'https://example.com/alpha-banner-mobile.png',
    'banner_url', 'https://example.com/alpha-banner.png',
    'display_name', 'Alpha Community List Communities',
    'logo_url', 'https://example.com/alpha-logo.png',
    'name', 'alpha-community-list-communities'
));
select fx_community(:'communityActiveBetaID', jsonb_build_object(
    'banner_mobile_url', 'https://example.com/beta-banner-mobile.png',
    'banner_url', 'https://example.com/beta-banner.png',
    'display_name', 'Beta Community',
    'logo_url', 'https://example.com/beta-logo.png',
    'name', 'beta-community'
));
select fx_community(:'communityInactiveID', jsonb_build_object('active', false));
select fx_community(:'communityNoGroupsID');
select fx_community(:'communityOnlyDeletedGroupID');
select fx_community(:'communityOnlyInactiveGroupID');

-- Group categories for communities with group fixtures
select fx_group_category(:'groupCategoryActiveAlphaID', :'communityActiveAlphaID');
select fx_group_category(:'groupCategoryActiveBetaID', :'communityActiveBetaID');
select fx_group_category(:'groupCategoryInactiveCommunityID', :'communityInactiveID');
select fx_group_category(:'groupCategoryOnlyDeletedID', :'communityOnlyDeletedGroupID');
select fx_group_category(:'groupCategoryOnlyInactiveID', :'communityOnlyInactiveGroupID');

-- Groups covering active, inactive, and deleted eligibility scenarios
select fx_group(:'groupActiveAlphaID', :'communityActiveAlphaID', :'groupCategoryActiveAlphaID');
select fx_group(:'groupActiveBetaID', :'communityActiveBetaID', :'groupCategoryActiveBetaID');
select fx_group(:'groupInactiveCommunityID', :'communityInactiveID', :'groupCategoryInactiveCommunityID');
select fx_group(:'groupOnlyDeletedID', :'communityOnlyDeletedGroupID', :'groupCategoryOnlyDeletedID', jsonb_build_object(
    'active', false,
    'deleted', true
));
select fx_group(:'groupOnlyInactiveID', :'communityOnlyInactiveGroupID', :'groupCategoryOnlyInactiveID', jsonb_build_object('active', false));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return active communities with active groups without requiring events
select is(
    list_communities()::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'banner_mobile_url', 'https://example.com/alpha-banner-mobile.png',
            'banner_url', 'https://example.com/alpha-banner.png',
            'community_id', :'communityActiveAlphaID',
            'display_name', 'Alpha Community List Communities',
            'logo_url', 'https://example.com/alpha-logo.png',
            'name', 'alpha-community-list-communities'
        ),
        jsonb_build_object(
            'banner_mobile_url', 'https://example.com/beta-banner-mobile.png',
            'banner_url', 'https://example.com/beta-banner.png',
            'community_id', :'communityActiveBetaID',
            'display_name', 'Beta Community',
            'logo_url', 'https://example.com/beta-logo.png',
            'name', 'beta-community'
        )
    ),
    'Should return active communities with active groups without requiring events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
