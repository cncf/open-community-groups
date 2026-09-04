-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '2c120000-0000-0000-0000-000000000001'
\set community2ID '2c120000-0000-0000-0000-000000000002'
\set community3ID '2c120000-0000-0000-0000-000000000003'
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

-- Baseline community and group category
select fx_community(:'community1ID');
select fx_community(:'community2ID');
select fx_community(:'community3ID');
select fx_group_category(:'groupCategory1ID', :'community1ID');
select fx_group_category(:'groupCategory2ID', :'community2ID');

insert into region (region_id, community_id, name, "order") values
    (:'region1ID', :'community1ID', 'North America', 2),
    (:'region2ID', :'community1ID', 'Europe', 1);

-- Regions (other community)
insert into region (region_id, community_id, name)
values (:'region3ID', :'community2ID', 'Asia Pacific');

-- Groups
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object('region_id', :'region2ID'));
-- group
select fx_group(:'group2ID', :'community1ID', :'groupCategory1ID', jsonb_build_object('region_id', :'region2ID'));
-- group
select fx_group(:'group3ID', :'community1ID', :'groupCategory1ID', jsonb_build_object('region_id', :'region1ID'));
-- group
select fx_group(:'group4ID', :'community2ID', :'groupCategory2ID', jsonb_build_object('region_id', :'region3ID'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete region data ordered by order field, then by name
select is(
    list_regions(:'community1ID'::uuid)::jsonb,
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

-- Should return empty array for community with no regions
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
