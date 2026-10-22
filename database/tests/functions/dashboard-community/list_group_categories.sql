-- Tests listing the group categories of a community with their group counts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '2c110000-0000-0000-0000-000000000001'
\set community2ID '2c110000-0000-0000-0000-000000000002'
\set community3ID '2c110000-0000-0000-0000-000000000003'
\set group1ID '2c110000-0000-0000-0000-000000000004'
\set group2ID '2c110000-0000-0000-0000-000000000005'
\set group3ID '2c110000-0000-0000-0000-000000000006'
\set group4ID '2c110000-0000-0000-0000-000000000007'
\set groupCategory1ID '2c110000-0000-0000-0000-000000000008'
\set groupCategory2ID '2c110000-0000-0000-0000-000000000009'
\set groupCategory3ID '2c110000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose group categories are listed
select fx_community(:'community1ID', jsonb_build_object(
    'display_name', 'Cloud Native Seattle List Group Categories',
    'name', 'cloud-native-seattle-list-group-categories'
));

-- Community whose group category and group are never listed
select fx_community(:'community2ID');

-- Community without group categories
select fx_community(:'community3ID');

-- Category listed first despite its name
select fx_group_category(:'groupCategory1ID', :'community1ID', jsonb_build_object(
    'name', 'Technology',
    'order', 1
));

-- Category listed second with two groups
select fx_group_category(:'groupCategory2ID', :'community1ID', jsonb_build_object(
    'name', 'Business',
    'order', 2
));

-- Group category of the other community
select fx_group_category(:'groupCategory3ID', :'community2ID');

-- Group counted in the Technology category
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'name', 'Cloud Native Seattle List Group Categories',
    'slug', 'cloud-native-seattle-list-group-categories'
));

-- First group counted in the Business category
select fx_group(:'group2ID', :'community1ID', :'groupCategory2ID');

-- Second group counted in the Business category
select fx_group(:'group3ID', :'community1ID', :'groupCategory2ID');

-- Group of the other community's category
select fx_group(:'group4ID', :'community2ID', :'groupCategory3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete category data ordered by order field, then by name
select is(
    list_group_categories(:'community1ID'::uuid)::jsonb,
    format(
        '[
        {
            "groups_count": 1,
            "group_category_id": "%s",
            "name": "Technology",
            "slug": "technology",
            "order": 1
        },
        {
            "groups_count": 2,
            "group_category_id": "%s",
            "name": "Business",
            "slug": "business",
            "order": 2
        }
    ]',
        :'groupCategory1ID',
        :'groupCategory2ID'
    )::jsonb,
    'Should return complete category data ordered by order field, then by name'
);

-- Should return empty array for community with no categories
select is(
    list_group_categories(:'community3ID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty array for community with no categories'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
