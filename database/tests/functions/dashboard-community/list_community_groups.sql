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
\set categoryID '00000000-0000-0000-0000-000000000011'
\set regionID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set group2ID '00000000-0000-0000-0000-000000000022'
\set group3ID '00000000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities (main and other for isolation testing)
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
    (
        :'community1ID',
        'cloud-native-seattle',
        'Cloud Native Seattle',
        'seattle.cloudnative.org',
        'Cloud Native Seattle Community',
        'A vibrant community for cloud native technologies and practices in Seattle',
        'https://example.com/logo.png',
        '{}'::jsonb
    ),
    (
        :'community2ID',
        'devops-vancouver',
        'DevOps Vancouver',
        'vancouver.devops.org',
        'DevOps Vancouver Community',
        'Building DevOps expertise and community in Vancouver',
        'https://example.com/logo2.png',
        '{}'::jsonb
    );

-- Group category (for organizing groups)
insert into group_category (group_category_id, name, "order", community_id)
values (:'categoryID', 'Technology', 1, :'community1ID');

-- Region (for geographic organization)
insert into region (region_id, name, "order", community_id)
values (:'regionID', 'North America', 1, :'community1ID');

-- Groups (for testing community isolation and ordering)
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id,
    created_at,
    city,
    state,
    country_code,
    country_name,
    logo_url,
    region_id
) values 
    (
        :'group1ID',
        :'community1ID',
        'Advanced Kubernetes',
        'advanced-kubernetes',
        'Deep dive into advanced Kubernetes concepts and patterns',
        :'categoryID',
        '2024-01-01 10:00:00+00',
        'San Francisco',
        'CA',
        'US',
        'United States',
        'https://example.com/k8s-logo.png',
        :'regionID'
    ),
    (
        :'group2ID',
        :'community1ID',
        'Zero Trust Security',
        'zero-trust-security',
        'Exploring zero trust security principles and implementation',
        :'categoryID',
        '2024-01-02 14:30:00+00',
        'New York',
        'NY',
        'US',
        'United States',
        null,
        null
    ),
    (
        :'group3ID',
        :'community2ID',
        'DevOps Best Practices',
        'devops-best-practices',
        'Sharing and learning DevOps best practices and tooling',
        :'categoryID',
        '2024-01-03 09:15:00+00',
        null,
        null,
        null,
        null,
        null,
        null
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- list_community_groups returns empty array for community with no groups
select is(
    list_community_groups('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'list_community_groups should return empty array for community with no groups'
);

-- list_community_groups returns full JSON structure for groups ordered alphabetically
select is(
    list_community_groups(:'community1ID'::uuid)::jsonb,
    '[
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology",
                "order": 1
            },
            "created_at": 1704103200,
            "group_id": "00000000-0000-0000-0000-000000000021",
            "name": "Advanced Kubernetes",
            "slug": "advanced-kubernetes",
            "city": "San Francisco",
            "country_code": "US",
            "country_name": "United States",
            "logo_url": "https://example.com/k8s-logo.png",
            "region": {
                "region_id": "00000000-0000-0000-0000-000000000012",
                "name": "North America",
                "normalized_name": "north-america",
                "order": 1
            },
            "state": "CA"
        },
        {
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology",
                "order": 1
            },
            "created_at": 1704205800,
            "group_id": "00000000-0000-0000-0000-000000000022",
            "name": "Zero Trust Security",
            "slug": "zero-trust-security",
            "city": "New York",
            "country_code": "US",
            "country_name": "United States",
            "state": "NY"
        }
    ]'::jsonb,
    'list_community_groups should return groups with full JSON structure ordered alphabetically by name'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
