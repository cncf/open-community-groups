-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'

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

-- Group Category
insert into group_category (group_category_id, name, community_id, "order")
values 
    (:'category1ID', 'Technology', :'community1ID', 2),
    (:'category2ID', 'Business', :'community1ID', 1);

-- Group Category (other community)
insert into group_category (group_category_id, name, community_id)
values 
    (:'category3ID', 'Education', :'community2ID');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    ('00000000-0000-0000-0000-000000000031', :'community1ID', :'category1ID', 'Cloud Native Seattle', 'cloud-native-seattle'),
    ('00000000-0000-0000-0000-000000000032', :'community1ID', :'category2ID', 'Business Builders', 'business-builders'),
    ('00000000-0000-0000-0000-000000000033', :'community1ID', :'category2ID', 'Startup Founders', 'startup-founders'),
    ('00000000-0000-0000-0000-000000000034', :'community2ID', :'category3ID', 'Education Collective', 'education-collective');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete category data ordered by order field, then by name
select is(
    list_group_categories(:'community1ID'::uuid)::jsonb,
    '[
        {
            "groups_count": 2,
            "group_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Business",
            "slug": "business",
            "order": 1
        },
        {
            "groups_count": 1,
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "slug": "technology",
            "order": 2
        }
    ]'::jsonb,
    'Should return complete category data ordered by order field, then by name'
);

-- Should return empty array for community with no categories
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
    'golang-austin',
    'Golang Austin',
    'Go programming language enthusiasts in Austin',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

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
