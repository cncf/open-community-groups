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
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'

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

-- Group categories (for main community with ordering)
insert into group_category (group_category_id, name, community_id, "order")
values 
    (:'category1ID', 'Technology', :'community1ID', 2),
    (:'category2ID', 'Business', :'community1ID', 1);

-- Group category (for other community isolation testing)
insert into group_category (group_category_id, name, community_id)
values 
    (:'category3ID', 'Education', :'community2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- list_group_categories returns complete JSON array with proper ordering
select is(
    list_group_categories(:'community1ID'::uuid)::jsonb,
    '[
        {
            "group_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Business",
            "slug": "business",
            "order": 1
        },
        {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "slug": "technology",
            "order": 2
        }
    ]'::jsonb,
    'list_group_categories should return complete category data ordered by order field, then by name'
);

-- list_group_categories returns empty array for community with no categories
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
    'golang-austin',
    'Golang Austin',
    'austin.golang.org',
    'Golang Austin Community',
    'Go programming language enthusiasts in Austin',
    'https://example.com/logo.png',
    '{}'::jsonb
);

select is(
    list_group_categories(:'community3ID'::uuid)::jsonb,
    '[]'::jsonb,
    'list_group_categories should return empty array for community with no categories'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
