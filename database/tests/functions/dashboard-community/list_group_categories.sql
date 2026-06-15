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

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner-mobile-1.png',
    'https://example.com/banner-1.png',
    'https://example.com/logo-1.png'
), (
    :'community2ID',
    'devops-vancouver',
    'DevOps Vancouver',
    'Building DevOps expertise and community in Vancouver',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
), (
    :'community3ID',
    'golang-austin',
    'Golang Austin',
    'Go programming language enthusiasts in Austin',
    'https://example.com/banner-mobile-3.png',
    'https://example.com/banner-3.png',
    'https://example.com/logo-3.png'
);

-- Group categories
insert into group_category (group_category_id, community_id, name, "order") values
    (:'groupCategory1ID', :'community1ID', 'Technology', 2),
    (:'groupCategory2ID', :'community1ID', 'Business', 1);

-- Group categories (other community)
insert into group_category (group_category_id, community_id, name)
values (:'groupCategory3ID', :'community2ID', 'Education');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'group1ID',
    :'community1ID',
    :'groupCategory1ID',
    'Cloud Native Seattle',
    'cloud-native-seattle'
), (
    :'group2ID',
    :'community1ID',
    :'groupCategory2ID',
    'Business Builders',
    'business-builders'
), (
    :'group3ID',
    :'community1ID',
    :'groupCategory2ID',
    'Startup Founders',
    'startup-founders'
), (
    :'group4ID',
    :'community2ID',
    :'groupCategory3ID',
    'Education Collective',
    'education-collective'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete category data ordered by order field, then by name
select is(
    list_group_categories(:'community1ID'::uuid)::jsonb,
    format(
        '[
        {
            "groups_count": 2,
            "group_category_id": "%s",
            "name": "Business",
            "slug": "business",
            "order": 1
        },
        {
            "groups_count": 1,
            "group_category_id": "%s",
            "name": "Technology",
            "slug": "technology",
            "order": 2
        }
    ]',
        :'groupCategory2ID',
        :'groupCategory1ID'
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
