-- Tests returning group summary information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c0b0000-0000-0000-0000-000000000001'
\set groupCategoryID '0c0b0000-0000-0000-0000-000000000002'
\set groupDeletedID '0c0b0000-0000-0000-0000-000000000003'
\set groupID '0c0b0000-0000-0000-0000-000000000004'
\set groupInactiveID '0c0b0000-0000-0000-0000-000000000005'
\set groupNoLogoID '0c0b0000-0000-0000-0000-00000000000a'
\set regionID '0c0b0000-0000-0000-0000-000000000006'
\set unknownCommunityID '0c0b0000-0000-0000-0000-000000000007'
\set unknownGroupID '0c0b0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Cloud Native Seattle Group Summary',
    'logo_dark_url', 'https://example.com/logo-dark.png',
    'logo_url', 'https://example.com/logo.png',
    'name', 'cloud-native-seattle-group-summary'
));

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Technology'));

-- Region
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'North America');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'banner_dark_url', 'https://example.com/group-banner-dark.png',
    'banner_mobile_dark_url', 'https://example.com/group-banner-mobile-dark.png',
    'banner_mobile_url', 'https://example.com/group-banner-mobile.png',
    'banner_url', 'https://example.com/group-banner.png',
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-15 10:00:00+00',
    'description_short', 'Seattle Kubernetes Meetup is the Seattle chapter for K8s enthusiasts',
    'location', ST_GeogFromText('POINT(-74.006 40.7128)'),
    'logo_dark_url', 'https://example.com/group-logo-dark.png',
    'logo_url', 'https://example.com/group-logo.png',
    'name', 'Seattle Kubernetes Meetup',
    'og_image_url', 'https://example.com/group-og.png',
    'region_id', :'regionID',
    'slug', 'abc1234',
    'state', 'NY'
));

-- Group (inactive)
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'created_at', '2024-02-15 10:00:00+00'
));

-- Group without a logo
select fx_group(:'groupNoLogoID', :'communityID', :'groupCategoryID');

-- Group (deleted)
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'created_at', '2024-02-15 10:00:00+00',
    'deleted', true,
    'deleted_at', '2024-03-15 10:00:00+00'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct group summary JSON
select is(
    get_group_summary(
        :'communityID'::uuid,
        :'groupID'::uuid
    )::jsonb,
    format('{
        "active": true,
        "category": {
            "group_category_id": "%s",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "community_display_name": "Cloud Native Seattle Group Summary",
        "community_name": "cloud-native-seattle-group-summary",
        "created_at": 1705312800,
        "group_id": "%s",
        "name": "Seattle Kubernetes Meetup",
        "slug": "abc1234",
        "banner_dark_url": "https://example.com/group-banner-dark.png",
        "banner_mobile_dark_url": "https://example.com/group-banner-mobile-dark.png",
        "banner_mobile_url": "https://example.com/group-banner-mobile.png",
        "banner_url": "https://example.com/group-banner.png",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description_short": "Seattle Kubernetes Meetup is the Seattle chapter for K8s enthusiasts",
        "latitude": 40.7128,
        "logo_dark_url": "https://example.com/group-logo-dark.png",
        "logo_url": "https://example.com/group-logo.png",
        "longitude": -74.006,
        "og_image_url": "https://example.com/group-og.png",
        "region": {
            "region_id": "%s",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "state": "NY"
    }', :'groupCategoryID', :'groupID', :'regionID')::jsonb,
    'Should return correct group summary data as JSON'
);

-- Should use community logo when group has no logo
select is(
    (get_group_summary(
        :'communityID'::uuid,
        :'groupNoLogoID'::uuid
    )::jsonb)->>'logo_url',
    'https://example.com/logo.png',
    'Should use community logo when group has no logo'
);

-- Should include pretty slug when available
update "group" set slug_pretty = 'seattle-kubernetes' where group_id = :'groupID';
select is(
    (get_group_summary(
        :'communityID'::uuid,
        :'groupID'::uuid
    )::jsonb)->>'slug_pretty',
    'seattle-kubernetes',
    'Should include pretty slug when available'
);

-- Should return null for non-existent group
select ok(
    get_group_summary(
        :'communityID'::uuid,
        :'unknownGroupID'::uuid
    ) is null,
    'Should return null for non-existent group ID'
);

-- Should return data for deleted group
select ok(
    get_group_summary(
        :'communityID'::uuid,
        :'groupDeletedID'::uuid
    ) is not null,
    'Should return data for deleted group'
);

-- Should return null when community does not match group
select ok(
    get_group_summary(
        :'unknownCommunityID'::uuid,
        :'groupID'::uuid
    ) is null,
    'Should return null when community does not match group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
