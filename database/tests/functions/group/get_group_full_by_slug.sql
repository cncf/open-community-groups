-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000031'
\set memberID '00000000-0000-0000-0000-000000000043'
\set organizer1ID '00000000-0000-0000-0000-000000000041'
\set organizer2ID '00000000-0000-0000-0000-000000000042'
\set regionID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url)
values (:'communityID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant community for cloud native technologies and practices in Seattle', 'https://example.com/logo.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Region
insert into region (region_id, name, community_id)
values (:'regionID', 'North America', :'communityID');

-- User
insert into "user" (user_id, auth_hash, email, username, created_at, bio, company, name, photo_url, title)
values
    (:'organizer1ID', 'test_hash', 'organizer1@example.com', 'organizer1', '2024-01-01 00:00:00', 'Group founder and speaker', 'Tech Corp', 'John Doe', 'https://example.com/john.png', 'CTO'),
    (:'organizer2ID', 'test_hash', 'organizer2@example.com', 'organizer2', '2024-01-01 00:00:00', 'Community events coordinator', 'Dev Inc', 'Jane Smith', 'https://example.com/jane.png', 'Lead Dev'),
    (:'memberID', 'test_hash', 'member@example.com', 'member1', '2024-01-01 00:00:00', null, 'StartUp', 'Bob Wilson', 'https://example.com/bob.png', 'Engineer');

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
    'abc1234',
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

-- Should return correct group data as JSON
select is(
    get_group_full_by_slug(:'communityID'::uuid, 'abc1234')::jsonb - '{created_at}'::text[],
    '{
        "active": true,
        "city": "New York",
        "name": "Kubernetes NYC",
        "slug": "abc1234",
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
                "bio": "Group founder and speaker",
                "name": "John Doe",
                "photo_url": "https://example.com/john.png"
            },
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "00000000-0000-0000-0000-000000000042",
                "username": "organizer2",
                "bio": "Community events coordinator",
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
    'Should return correct group data as JSON'
);

-- Should return null with non-existing group slug
select ok(
    get_group_full_by_slug(:'communityID'::uuid, 'non-existing-group') is null,
    'Should return null with non-existing group slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
