-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set regionID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set organizer1ID '00000000-0000-0000-0000-000000000041'
\set organizer2ID '00000000-0000-0000-0000-000000000042'
\set memberID '00000000-0000-0000-0000-000000000043'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Region
insert into region (region_id, name, community_id)
values (:'regionID', 'North America', :'communityID');

-- User
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, name, company, title, photo_url, created_at)
values
    (:'organizer1ID', 'organizer1@example.com', 'organizer1', false, 'test_hash', :'communityID', 'John Doe', 'Tech Corp', 'CTO', 'https://example.com/john.png', '2024-01-01 00:00:00'),
    (:'organizer2ID', 'organizer2@example.com', 'organizer2', false, 'test_hash', :'communityID', 'Jane Smith', 'Dev Inc', 'Lead Dev', 'https://example.com/jane.png', '2024-01-01 00:00:00'),
    (:'memberID', 'member@example.com', 'member1', false, 'test_hash', :'communityID', 'Bob Wilson', 'StartUp', 'Engineer', 'https://example.com/bob.png', '2024-01-01 00:00:00');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    region_id,
    description,
    logo_url,
    banner_url,
    city,
    state,
    country_code,
    country_name,
    location,
    tags,
    website_url,
    facebook_url,
    twitter_url,
    linkedin_url,
    github_url
) values (
    :'groupID',
    'Kubernetes NYC',
    'kubernetes-nyc',
    :'communityID',
    :'categoryID',
    :'regionID',
    'New York Kubernetes meetup group for cloud native enthusiasts',
    'https://example.com/k8s-logo.png',
    'https://example.com/k8s-banner.png',
    'New York',
    'NY',
    'US',
    'United States',
    ST_GeogFromText('POINT(-74.0060 40.7128)'),
    array['kubernetes', 'cloud-native', 'devops'],
    'https://k8s-nyc.example.com',
    'https://facebook.com/k8snyc',
    'https://twitter.com/k8snyc',
    'https://linkedin.com/company/k8snyc',
    'https://github.com/k8snyc'
);

-- Group Member
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'organizer1ID', '2024-01-01 00:00:00'),
    (:'groupID', :'organizer2ID', '2024-01-01 00:00:00'),
    (:'groupID', :'memberID', '2024-01-01 00:00:00');

-- Group Team
insert into group_team (group_id, user_id, role, accepted, "order", created_at)
values
    (:'groupID', :'organizer1ID', 'organizer', true, 1, '2024-01-01 00:00:00'),
    (:'groupID', :'organizer2ID', 'organizer', true, 2, '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- get_group function returns correct data
select is(
    get_group(:'communityID'::uuid, 'kubernetes-nyc')::jsonb - '{created_at}'::text[],
    '{
        "active": true,
        "city": "New York",
        "name": "Kubernetes NYC",
        "slug": "kubernetes-nyc",
        "tags": ["kubernetes", "cloud-native", "devops"],
        "state": "NY",
        "group_id": "00000000-0000-0000-0000-000000000031",
        "latitude": 40.7128,
        "logo_url": "https://example.com/k8s-logo.png",
        "sponsors": [],
        "longitude": -74.006,
        "banner_url": "https://example.com/k8s-banner.png",
        "github_url": "https://github.com/k8snyc",
        "organizers": [
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "00000000-0000-0000-0000-000000000041",
                "username": "organizer1",
                "name": "John Doe",
                "photo_url": "https://example.com/john.png"
            },
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "00000000-0000-0000-0000-000000000042",
                "username": "organizer2",
                "name": "Jane Smith",
                "photo_url": "https://example.com/jane.png"
            }
        ],
        "description": "New York Kubernetes meetup group for cloud native enthusiasts",
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000021",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "twitter_url": "https://twitter.com/k8snyc",
        "website_url": "https://k8s-nyc.example.com",
        "country_code": "US",
        "country_name": "United States",
        "facebook_url": "https://facebook.com/k8snyc",
        "linkedin_url": "https://linkedin.com/company/k8snyc",
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "members_count": 3
    }'::jsonb,
    'get_group should return correct group data as JSON'
);

-- get_group with non-existing group slug
select ok(
    get_group(:'communityID'::uuid, 'non-existing-group') is null,
    'get_group with non-existing group slug should return null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
