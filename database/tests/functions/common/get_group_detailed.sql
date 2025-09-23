-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set regionID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
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
    description_short,
    logo_url,
    location,
    created_at
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'seattle-kubernetes-meetup',
    :'communityID',
    :'categoryID',
    :'regionID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'A brief overview of the Seattle Kubernetes group',
    'https://example.com/group-logo.png',
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
    'inactive-devops-group',
    :'communityID',
    :'categoryID',
    false,
    '2024-02-15 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_group_detailed should return correct detailed group JSON
select is(
    get_group_detailed(
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
        "slug": "seattle-kubernetes-meetup",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description_short": "A brief overview of the Seattle Kubernetes group",
        "latitude": 40.7128,
        "logo_url": "https://example.com/group-logo.png",
        "longitude": -74.006,
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "state": "NY"
    }'::jsonb,
    'get_group_detailed should return correct detailed group data with location as JSON'
);

-- Test: get_group_detailed with non-existent group should return null
select ok(
    get_group_detailed(
        :'communityID'::uuid,
        '00000000-0000-0000-0000-000000999999'::uuid
    ) is null,
    'get_group_detailed with non-existent group ID should return null'
);

-- Test: get_group_detailed should return null when community does not match group
select ok(
    get_group_detailed(
        '00000000-0000-0000-0000-000000000002'::uuid,
        :'groupID'::uuid
    ) is null,
    'get_group_detailed should return null when community does not match group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
