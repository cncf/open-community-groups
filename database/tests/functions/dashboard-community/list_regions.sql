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

-- Communities (main and others for isolation testing)
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values 
    (:'community1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'seattle.cloudnative.org', 'Cloud Native Seattle Community', 'A vibrant community for cloud native technologies and practices in Seattle', 'https://example.com/logo1.png', '{}'::jsonb),
    (:'community2ID', 'devops-vancouver', 'DevOps Vancouver', 'vancouver.devops.org', 'DevOps Vancouver Community', 'Building DevOps expertise and community in Vancouver', 'https://example.com/logo2.png', '{}'::jsonb);

-- Regions (for main community with ordering)
insert into region (region_id, name, community_id, "order")
values 
    (:'region1ID', 'North America', :'community1ID', 2),
    (:'region2ID', 'Europe', :'community1ID', 1);

-- Region (for other community isolation testing)
insert into region (region_id, name, community_id)
values 
    (:'region3ID', 'Asia Pacific', :'community2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- list_regions returns complete JSON array with proper ordering
select is(
    list_regions(:'community1ID'::uuid)::jsonb,
    '[
        {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "Europe",
            "normalized_name": "europe",
            "order": 1
        },
        {
            "region_id": "00000000-0000-0000-0000-000000000011",
            "name": "North America",
            "normalized_name": "north-america",
            "order": 2
        }
    ]'::jsonb,
    'list_regions should return complete region data ordered by order field, then by name'
);

-- list_regions returns empty array for community with no regions
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
    :'community3ID'::uuid,
    'rust-denver',
    'Rust Denver',
    'denver.rust-lang.org',
    'Rust Denver Community',
    'Building the Rust programming community in Denver',
    'https://example.com/logo.png',
    '{}'::jsonb
);

select is(
    list_regions(:'community3ID'::uuid)::jsonb,
    '[]'::jsonb,
    'list_regions should return empty array for community with no regions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
