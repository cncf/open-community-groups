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
\set regionID '0c0b0000-0000-0000-0000-000000000006'
\set unknownCommunityID '0c0b0000-0000-0000-0000-000000000007'
\set unknownGroupID '0c0b0000-0000-0000-0000-000000000008'

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
    logo_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Region
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'North America');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    region_id,
    active,
    banner_url,
    city,
    state,
    country_code,
    country_name,
    logo_url,
    og_image_url,
    description_short,
    location,
    created_at
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Seattle Kubernetes Meetup',
    'abc1234',

    :'regionID',
    true,
    'https://example.com/group-banner.png',
    'New York',
    'NY',
    'US',
    'United States',
    'https://example.com/group-logo.png',
    'https://example.com/group-og.png',
    'Seattle Kubernetes Meetup is the Seattle chapter for K8s enthusiasts',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '2024-01-15 10:00:00+00'
);

-- Group (inactive)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    active,
    created_at
) values (
    :'groupInactiveID',
    :'communityID',
    :'groupCategoryID',
    'Inactive DevOps Group',
    'xyz9876',

    false,
    '2024-02-15 10:00:00+00'
);

-- Group (deleted)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    active,
    deleted,
    deleted_at,
    created_at
) values (
    :'groupDeletedID',
    :'communityID',
    :'groupCategoryID',
    'Deleted DevOps Group',
    'mno3ghi',

    false,
    true,
    '2024-03-15 10:00:00+00',
    '2024-02-15 10:00:00+00'
);

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
        "community_display_name": "Cloud Native Seattle",
        "community_name": "cloud-native-seattle",
        "created_at": 1705312800,
        "group_id": "%s",
        "name": "Seattle Kubernetes Meetup",
        "slug": "abc1234",
        "banner_url": "https://example.com/group-banner.png",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description_short": "Seattle Kubernetes Meetup is the Seattle chapter for K8s enthusiasts",
        "logo_url": "https://example.com/group-logo.png",
        "latitude": 40.7128,
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
update "group" set logo_url = null where group_id = :'groupID';
select is(
    (get_group_summary(
        :'communityID'::uuid,
        :'groupID'::uuid
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
