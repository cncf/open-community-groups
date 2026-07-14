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
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values
    (
        :'communityActiveAlphaID',
        true,
        'https://example.com/alpha-banner-mobile.png',
        'https://example.com/alpha-banner.png',
        'Active community with an active group and no events',
        'Alpha Community',
        'https://example.com/alpha-logo.png',
        'alpha-community'
    ),
    (
        :'communityActiveBetaID',
        true,
        'https://example.com/beta-banner-mobile.png',
        'https://example.com/beta-banner.png',
        'Second active community with an active group and no events',
        'Beta Community',
        'https://example.com/beta-logo.png',
        'beta-community'
    ),
    (
        :'communityInactiveID',
        false,
        'https://example.com/inactive-banner-mobile.png',
        'https://example.com/inactive-banner.png',
        'Inactive community with an active group',
        'Inactive Community',
        'https://example.com/inactive-logo.png',
        'inactive-community'
    ),
    (
        :'communityNoGroupsID',
        true,
        'https://example.com/no-groups-banner-mobile.png',
        'https://example.com/no-groups-banner.png',
        'Active community without groups',
        'No Groups Community',
        'https://example.com/no-groups-logo.png',
        'no-groups-community'
    ),
    (
        :'communityOnlyDeletedGroupID',
        true,
        'https://example.com/deleted-group-banner-mobile.png',
        'https://example.com/deleted-group-banner.png',
        'Active community with only a deleted group',
        'Only Deleted Group Community',
        'https://example.com/deleted-group-logo.png',
        'only-deleted-group-community'
    ),
    (
        :'communityOnlyInactiveGroupID',
        true,
        'https://example.com/inactive-group-banner-mobile.png',
        'https://example.com/inactive-group-banner.png',
        'Active community with only an inactive group',
        'Only Inactive Group Community',
        'https://example.com/inactive-group-logo.png',
        'only-inactive-group-community'
    );

-- Group categories for communities with group fixtures
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryActiveAlphaID', :'communityActiveAlphaID', 'Technology'),
    (:'groupCategoryActiveBetaID', :'communityActiveBetaID', 'Technology'),
    (:'groupCategoryInactiveCommunityID', :'communityInactiveID', 'Technology'),
    (:'groupCategoryOnlyDeletedID', :'communityOnlyDeletedGroupID', 'Technology'),
    (:'groupCategoryOnlyInactiveID', :'communityOnlyInactiveGroupID', 'Technology');

-- Groups covering active, inactive, and deleted eligibility scenarios
insert into "group" (
    group_id,
    active,
    community_id,
    deleted,
    group_category_id,
    name,
    slug
) values
    (
        :'groupActiveAlphaID',
        true,
        :'communityActiveAlphaID',
        false,
        :'groupCategoryActiveAlphaID',
        'Alpha Group',
        'alpha-group'
    ),
    (
        :'groupActiveBetaID',
        true,
        :'communityActiveBetaID',
        false,
        :'groupCategoryActiveBetaID',
        'Beta Group',
        'beta-group'
    ),
    (
        :'groupInactiveCommunityID',
        true,
        :'communityInactiveID',
        false,
        :'groupCategoryInactiveCommunityID',
        'Inactive Community Group',
        'inactive-community-group'
    ),
    (
        :'groupOnlyDeletedID',
        false,
        :'communityOnlyDeletedGroupID',
        true,
        :'groupCategoryOnlyDeletedID',
        'Deleted Group',
        'deleted-group'
    ),
    (
        :'groupOnlyInactiveID',
        false,
        :'communityOnlyInactiveGroupID',
        false,
        :'groupCategoryOnlyInactiveID',
        'Inactive Group',
        'inactive-group'
    );

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
            'display_name', 'Alpha Community',
            'logo_url', 'https://example.com/alpha-logo.png',
            'name', 'alpha-community'
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
