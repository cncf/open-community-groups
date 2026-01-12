-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupDeletedID '00000000-0000-0000-0000-000000000023'
\set groupID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set regionID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    'https://example.com/banner.png'
);

-- Region
insert into region (region_id, name, community_id)
values (:'regionID', 'North America', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    region_id,
    active,
    city,
    state,
    country_code,
    country_name,
    logo_url,
    description_short,
    location,
    created_at
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'abc1234',
    :'communityID',
    :'categoryID',
    :'regionID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'https://example.com/group-logo.png',
    'Seattle Kubernetes Meetup is the Seattle chapter for K8s enthusiasts',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '2024-01-15 10:00:00+00'
);

-- Group (inactive)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    created_at
) values (
    :'groupInactiveID',
    'Inactive DevOps Group',
    'xyz9876',
    :'communityID',
    :'categoryID',
    false,
    '2024-02-15 10:00:00+00'
);

-- Group (deleted)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    deleted,
    deleted_at,
    created_at
) values (
    :'groupDeletedID',
    'Deleted DevOps Group',
    'mno3ghi',
    :'communityID',
    :'categoryID',
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
    '{
        "active": true,
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "created_at": 1705312800,
        "group_id": "00000000-0000-0000-0000-000000000021",
        "name": "Seattle Kubernetes Meetup",
        "slug": "abc1234",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description_short": "Seattle Kubernetes Meetup is the Seattle chapter for K8s enthusiasts",
        "logo_url": "https://example.com/group-logo.png",
        "latitude": 40.7128,
        "longitude": -74.006,
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "state": "NY"
    }'::jsonb,
    'Should return correct group summary data as JSON'
);

-- Should return null for non-existent group
select ok(
    get_group_summary(
        :'communityID'::uuid,
        '00000000-0000-0000-0000-000000999999'::uuid
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
        '00000000-0000-0000-0000-000000000002'::uuid,
        :'groupID'::uuid
    ) is null,
    'Should return null when community does not match group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
