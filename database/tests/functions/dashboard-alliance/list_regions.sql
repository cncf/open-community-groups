-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '2c120000-0000-0000-0000-000000000001'
\set alliance2ID '2c120000-0000-0000-0000-000000000002'
\set alliance3ID '2c120000-0000-0000-0000-000000000003'
\set group1ID '2c120000-0000-0000-0000-000000000004'
\set group2ID '2c120000-0000-0000-0000-000000000005'
\set group3ID '2c120000-0000-0000-0000-000000000006'
\set group4ID '2c120000-0000-0000-0000-000000000007'
\set groupCategory1ID '2c120000-0000-0000-0000-000000000008'
\set groupCategory2ID '2c120000-0000-0000-0000-000000000009'
\set region1ID '2c120000-0000-0000-0000-000000000010'
\set region2ID '2c120000-0000-0000-0000-000000000011'
\set region3ID '2c120000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/banner-mobile-1.png',
    'https://example.com/banner-1.png',
    'https://example.com/logo-1.png'
), (
    :'alliance2ID',
    'devops-vancouver',
    'DevOps Vancouver',
    'Building DevOps expertise and alliance in Vancouver',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
), (
    :'alliance3ID',
    'rust-denver',
    'Rust Denver',
    'Building the Rust programming alliance in Denver',
    'https://example.com/banner-mobile-3.png',
    'https://example.com/banner-3.png',
    'https://example.com/logo-3.png'
);

-- Regions
insert into region (region_id, alliance_id, name, "order") values
    (:'region1ID', :'alliance1ID', 'North America', 2),
    (:'region2ID', :'alliance1ID', 'Europe', 1);

-- Regions (other alliance)
insert into region (region_id, alliance_id, name)
values (:'region3ID', :'alliance2ID', 'Asia Pacific');

-- Group categories
insert into group_category (group_category_id, alliance_id, name) values
    (:'groupCategory1ID', :'alliance1ID', 'Technology'),
    (:'groupCategory2ID', :'alliance2ID', 'Business');

-- Groups
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    region_id
) values (
    :'group1ID',
    :'alliance1ID',
    :'groupCategory1ID',
    'Europe JS',
    'europe-js',
    :'region2ID'
), (
    :'group2ID',
    :'alliance1ID',
    :'groupCategory1ID',
    'Europe Rust',
    'europe-rust',
    :'region2ID'
), (
    :'group3ID',
    :'alliance1ID',
    :'groupCategory1ID',
    'North America Go',
    'north-america-go',
    :'region1ID'
), (
    :'group4ID',
    :'alliance2ID',
    :'groupCategory2ID',
    'APAC DevOps',
    'apac-devops',
    :'region3ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete region data ordered by order field, then by name
select is(
    list_regions(:'alliance1ID'::uuid)::jsonb,
    format(
        '[
        {
            "groups_count": 2,
            "region_id": "%s",
            "name": "Europe",
            "normalized_name": "europe",
            "order": 1
        },
        {
            "groups_count": 1,
            "region_id": "%s",
            "name": "North America",
            "normalized_name": "north-america",
            "order": 2
        }
    ]',
        :'region2ID',
        :'region1ID'
    )::jsonb,
    'Should return complete region data ordered by order field, then by name'
);

-- Should return empty array for alliance with no regions
select is(
    list_regions(:'alliance3ID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty array for alliance with no regions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
