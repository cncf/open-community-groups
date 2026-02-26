-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'
\set region1ID '00000000-0000-0000-0000-000000000011'
\set region2ID '00000000-0000-0000-0000-000000000012'
\set region3ID '00000000-0000-0000-0000-000000000013'

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
    banner_mobile_url,
    banner_url
) values
    (:'community1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant community for cloud native technologies and practices in Seattle', 'https://example.com/logo1.png', 'https://example.com/banner_mobile1.png', 'https://example.com/banner1.png'),
    (:'community2ID', 'devops-vancouver', 'DevOps Vancouver', 'Building DevOps expertise and community in Vancouver', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- Region
insert into region (region_id, name, community_id, "order")
values 
    (:'region1ID', 'North America', :'community1ID', 2),
    (:'region2ID', 'Europe', :'community1ID', 1);

-- Region (other community)
insert into region (region_id, name, community_id)
values 
    (:'region3ID', 'Asia Pacific', :'community2ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values
    ('00000000-0000-0000-0000-000000000021', 'Technology', :'community1ID'),
    ('00000000-0000-0000-0000-000000000022', 'Business', :'community2ID');

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    region_id,
    slug
)
values
    ('00000000-0000-0000-0000-000000000031', :'community1ID', '00000000-0000-0000-0000-000000000021', 'Europe JS', :'region2ID', 'europe-js'),
    ('00000000-0000-0000-0000-000000000032', :'community1ID', '00000000-0000-0000-0000-000000000021', 'Europe Rust', :'region2ID', 'europe-rust'),
    ('00000000-0000-0000-0000-000000000033', :'community1ID', '00000000-0000-0000-0000-000000000021', 'North America Go', :'region1ID', 'north-america-go'),
    ('00000000-0000-0000-0000-000000000034', :'community2ID', '00000000-0000-0000-0000-000000000022', 'APAC DevOps', :'region3ID', 'apac-devops');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete region data ordered by order field, then by name
select is(
    list_regions(:'community1ID'::uuid)::jsonb,
    '[
        {
            "groups_count": 2,
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "Europe",
            "normalized_name": "europe",
            "order": 1
        },
        {
            "groups_count": 1,
            "region_id": "00000000-0000-0000-0000-000000000011",
            "name": "North America",
            "normalized_name": "north-america",
            "order": 2
        }
    ]'::jsonb,
    'Should return complete region data ordered by order field, then by name'
);

-- Should return empty array for community with no regions
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'community3ID'::uuid,
    'rust-denver',
    'Rust Denver',
    'Building the Rust programming community in Denver',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

select is(
    list_regions(:'community3ID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty array for community with no regions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
