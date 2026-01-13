-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'

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
    banner_url
) values
    (:'community1ID', 'alpha-community', 'Alpha Community', 'First community', 'https://example.com/alpha-logo.png', 'https://example.com/alpha-banner.png'),
    (:'community2ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant community', 'https://example.com/cns-logo.png', 'https://example.com/cns-banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id, "order")
values
    (:'category1ID', 'Technology', :'community2ID', 1),
    (:'category2ID', 'Business', :'community2ID', 2);

-- Region
insert into region (region_id, name, community_id, "order")
values
    (:'region1ID', 'North America', :'community2ID', 1),
    (:'region2ID', 'Europe', :'community2ID', 2);

-- Event Category
insert into event_category (event_category_id, name, slug, community_id, "order")
values
    ('00000000-0000-0000-0000-000000000061', 'Tech Talks', 'tech-talks', :'community2ID', 1),
    ('00000000-0000-0000-0000-000000000062', 'Workshops', 'workshops', :'community2ID', 2),
    ('00000000-0000-0000-0000-000000000063', 'Conferences', 'conferences', :'community2ID', 3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return communities and distance options when no community_id is provided
select is(
    get_filters_options()::jsonb,
    '{
        "communities": [
            {
                "banner_url": "https://example.com/alpha-banner.png",
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Alpha Community",
                "logo_url": "https://example.com/alpha-logo.png",
                "name": "alpha-community"
            },
            {
                "banner_url": "https://example.com/cns-banner.png",
                "community_id": "00000000-0000-0000-0000-000000000002",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/cns-logo.png",
                "name": "cloud-native-seattle"
            }
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ]
    }'::jsonb,
    'Should return communities and distance options when no community_id is provided'
);

-- Should return all filter options when a valid community name is provided
select is(
    get_filters_options('cloud-native-seattle')::jsonb,
    '{
        "communities": [
            {
                "banner_url": "https://example.com/alpha-banner.png",
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Alpha Community",
                "logo_url": "https://example.com/alpha-logo.png",
                "name": "alpha-community"
            },
            {
                "banner_url": "https://example.com/cns-banner.png",
                "community_id": "00000000-0000-0000-0000-000000000002",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/cns-logo.png",
                "name": "cloud-native-seattle"
            }
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [
            {"name": "Tech Talks", "value": "tech-talks"},
            {"name": "Workshops", "value": "workshops"},
            {"name": "Conferences", "value": "conferences"}
        ],
        "group_category": [
            {"name": "Technology", "value": "technology"},
            {"name": "Business", "value": "business"}
        ],
        "region": [
            {"name": "North America", "value": "north-america"},
            {"name": "Europe", "value": "europe"}
        ]
    }'::jsonb,
    'Should return all filter options when a valid community_name is provided'
);

-- Should return communities, distance and empty arrays for non-existing community
select is(
    get_filters_options('non-existent-community')::jsonb,
    '{
        "communities": [
            {
                "banner_url": "https://example.com/alpha-banner.png",
                "community_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Alpha Community",
                "logo_url": "https://example.com/alpha-logo.png",
                "name": "alpha-community"
            },
            {
                "banner_url": "https://example.com/cns-banner.png",
                "community_id": "00000000-0000-0000-0000-000000000002",
                "display_name": "Cloud Native Seattle",
                "logo_url": "https://example.com/cns-logo.png",
                "name": "cloud-native-seattle"
            }
        ],
        "distance": [
            {"name": "10 km", "value": "10000"},
            {"name": "50 km", "value": "50000"},
            {"name": "100 km", "value": "100000"},
            {"name": "500 km", "value": "500000"},
            {"name": "1000 km", "value": "1000000"}
        ],
        "event_category": [],
        "group_category": [],
        "region": []
    }'::jsonb,
    'Should return communities, distance and empty arrays for non-existing community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
