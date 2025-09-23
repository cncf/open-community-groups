-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set regionID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set sponsor1ID '00000000-0000-0000-0000-000000000041'
\set sponsor2ID '00000000-0000-0000-0000-000000000042'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'

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

-- Region
insert into region (region_id, name, community_id)
values (:'regionID', 'North America', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- User
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, bio, name, photo_url, company, title, facebook_url, linkedin_url, twitter_url, website_url)
values
    (:'user1ID', 'alice@seattle.cloudnative.org', 'alice-organizer', false, 'test_hash', :'communityID', 'Community meetup organizer', 'Alice Johnson', 'https://example.com/alice.png', 'Cloud Co', 'Manager', 'https://facebook.com/alice', 'https://linkedin.com/in/alice', 'https://twitter.com/alice', 'https://alice.com'),
    (:'user2ID', 'bob@seattle.cloudnative.org', 'bob-organizer', false, 'test_hash', :'communityID', 'Cloud native program lead', 'Bob Wilson', 'https://example.com/bob.png', 'StartUp', 'Engineer', null, 'https://linkedin.com/in/bob', null, 'https://bob.com'),
    (:'user3ID', 'charlie@seattle.cloudnative.org', 'charlie-member', false, 'test_hash', :'communityID', null, 'Charlie Brown', null, null, null, null, null, null, null),
    (:'user4ID', 'diana@seattle.cloudnative.org', 'diana-member', false, 'test_hash', :'communityID', null, 'Diana Prince', null, null, null, null, null, null, null);

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    region_id,
    active,
    city,
    state,
    country_code,
    country_name,
    description,
    description_short,
    logo_url,
    banner_url,
    location,
    tags,
    website_url,
    facebook_url,
    twitter_url,
    linkedin_url,
    github_url,
    instagram_url,
    youtube_url,
    slack_url,
    flickr_url,
    wechat_url,
    photos_urls,
    extra_links,
    created_at
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'seattle-kubernetes-meetup',
    :'communityID',
    :'categoryID',
    :'regionID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'A technology group focused on Kubernetes and cloud native technologies',
    'A brief overview of the Seattle Kubernetes group',
    'https://example.com/group-logo.png',
    'https://example.com/group-banner.png',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    array['kubernetes', 'cloud-native', 'containers'],
    'https://seattle.kubernetes.com',
    'https://facebook.com/seattlek8s',
    'https://twitter.com/seattlek8s',
    'https://linkedin.com/company/seattlek8s',
    'https://github.com/seattlek8s',
    'https://instagram.com/seattlek8s',
    'https://youtube.com/@seattlek8s',
    'https://seattlek8s.slack.com',
    'https://flickr.com/seattlek8s',
    'https://wechat.com/seattlek8s',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    jsonb '[{"name": "Discord", "url": "https://discord.gg/seattlek8s"}, {"name": "Forum", "url": "https://forum.seattlek8s.com"}]',
    '2024-01-15 10:00:00+00'
);

-- Group Sponsor
insert into group_sponsor (
    group_sponsor_id,
    group_id,
    logo_url,
    name,
    website_url
) values
    (:'sponsor1ID', :'groupID', 'https://example.com/logos/devops-tools.png', 'DevOps Tools Inc', 'https://devopstools.example.com'),
    (:'sponsor2ID', :'groupID', 'https://example.com/logos/kube-corp.png', 'Kube Corp', null);

-- Group Team
insert into group_team (group_id, user_id, role, accepted, "order")
values
    (:'groupID', :'user1ID', 'organizer', true, 1),
    (:'groupID', :'user2ID', 'organizer', true, 2);

-- Group Member
insert into group_member (group_id, user_id)
values
    (:'groupID', :'user1ID'),
    (:'groupID', :'user2ID'),
    (:'groupID', :'user3ID'),
    (:'groupID', :'user4ID');

-- Group (inactive)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    created_at
) values (
    :'groupInactiveID',
    'Inactive DevOps Group',
    'inactive-devops-group',
    :'communityID',
    :'categoryID',
    false,
    '2024-02-15 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_group_full should return complete group JSON
select is(
    get_group_full(
        :'communityID'::uuid,
        :'groupID'::uuid
    )::jsonb,
    '{
        "active": true,
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "created_at": 1705312800,
        "group_id": "00000000-0000-0000-0000-000000000021",
        "members_count": 4,
        "name": "Seattle Kubernetes Meetup",
        "slug": "seattle-kubernetes-meetup",
        "banner_url": "https://example.com/group-banner.png",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description": "A technology group focused on Kubernetes and cloud native technologies",
        "description_short": "A brief overview of the Seattle Kubernetes group",
        "extra_links": [{"name": "Discord", "url": "https://discord.gg/seattlek8s"}, {"name": "Forum", "url": "https://forum.seattlek8s.com"}],
        "facebook_url": "https://facebook.com/seattlek8s",
        "flickr_url": "https://flickr.com/seattlek8s",
        "github_url": "https://github.com/seattlek8s",
        "instagram_url": "https://instagram.com/seattlek8s",
        "latitude": 40.7128,
        "linkedin_url": "https://linkedin.com/company/seattlek8s",
        "logo_url": "https://example.com/group-logo.png",
        "longitude": -74.006,
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "slack_url": "https://seattlek8s.slack.com",
        "state": "NY",
        "tags": ["kubernetes", "cloud-native", "containers"],
        "twitter_url": "https://twitter.com/seattlek8s",
        "wechat_url": "https://wechat.com/seattlek8s",
        "website_url": "https://seattle.kubernetes.com",
        "youtube_url": "https://youtube.com/@seattlek8s",
        "organizers": [
            {
                "user_id": "00000000-0000-0000-0000-000000000031",
                "username": "alice-organizer",
                "bio": "Community meetup organizer",
                "name": "Alice Johnson",
                "company": "Cloud Co",
                "facebook_url": "https://facebook.com/alice",
                "linkedin_url": "https://linkedin.com/in/alice",
                "photo_url": "https://example.com/alice.png",
                "title": "Manager",
                "twitter_url": "https://twitter.com/alice",
                "website_url": "https://alice.com"
            },
            {
                "user_id": "00000000-0000-0000-0000-000000000032",
                "username": "bob-organizer",
                "bio": "Cloud native program lead",
                "name": "Bob Wilson",
                "company": "StartUp",
                "linkedin_url": "https://linkedin.com/in/bob",
                "photo_url": "https://example.com/bob.png",
                "title": "Engineer",
                "website_url": "https://bob.com"
            }
        ],
        "sponsors": [
            {
                "group_sponsor_id": "00000000-0000-0000-0000-000000000041",
                "logo_url": "https://example.com/logos/devops-tools.png",
                "name": "DevOps Tools Inc",
                "website_url": "https://devopstools.example.com"
            },
            {
                "group_sponsor_id": "00000000-0000-0000-0000-000000000042",
                "logo_url": "https://example.com/logos/kube-corp.png",
                "name": "Kube Corp"
            }
        ]
    }'::jsonb,
    'get_group_full should return complete group data with organizers and member count as JSON'
);

-- Test: get_group_full with non-existent group should return null
select ok(
    get_group_full(
        :'communityID'::uuid,
        '00000000-0000-0000-0000-000000999999'::uuid
    ) is null,
    'get_group_full with non-existent group ID should return null'
);

-- Test: get_group_full should return null when community does not match group
select ok(
    get_group_full(
        '00000000-0000-0000-0000-000000000002'::uuid,
        :'groupID'::uuid
    ) is null,
    'get_group_full should return null when community does not match group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
