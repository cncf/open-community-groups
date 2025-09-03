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
\set groupDeletedID '00000000-0000-0000-0000-000000000023'

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
    logo_url,
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
    'https://example.com/group-logo.png',
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
    'deleted-devops-group',
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

-- Test: get_group_summary should return correct group summary JSON
select is(
    get_group_summary('00000000-0000-0000-0000-000000000021'::uuid)::jsonb,
    '{
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
        "logo_url": "https://example.com/group-logo.png",
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "state": "NY"
    }'::jsonb,
    'get_group_summary should return correct group summary data as JSON'
);

-- Test: get_group_summary with non-existent group should return null
select ok(
    get_group_summary('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_group_summary with non-existent group ID should return null'
);

-- Test: get_group_summary with deleted group should return data
select ok(
    get_group_summary('00000000-0000-0000-0000-000000000023'::uuid) is not null,
    'get_group_summary with deleted group ID should return data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
