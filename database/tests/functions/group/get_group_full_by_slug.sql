-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '6a010000-0000-0000-0000-000000000001'
\set groupCategoryID '6a010000-0000-0000-0000-000000000002'
\set groupID '6a010000-0000-0000-0000-000000000003'
\set memberID '6a010000-0000-0000-0000-000000000004'
\set organizer1ID '6a010000-0000-0000-0000-000000000005'
\set organizer2ID '6a010000-0000-0000-0000-000000000006'
\set regionID '6a010000-0000-0000-0000-000000000007'
\set sponsor1ID '6a010000-0000-0000-0000-000000000008'
\set sponsor2ID '6a010000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,
    og_image_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png',
    'https://example.com/alliance-og.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Region
insert into region (region_id, name, alliance_id)
values (:'regionID', 'North America', :'allianceID');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    created_at,
    bio,
    company,
    name,
    photo_url,
    title
)
values
    (
        :'organizer1ID',
        'test_hash',
        'organizer1@example.com',
        true,
        'organizer1',
        '2024-01-01 00:00:00',
        'Group founder and speaker',
        'Tech Corp',
        'John Doe',
        'https://example.com/john.png',
        'CTO'
    ),
    (
        :'organizer2ID',
        'test_hash',
        'organizer2@example.com',
        true,
        'organizer2',
        '2024-01-01 00:00:00',
        'Alliance events coordinator',
        'Dev Inc',
        'Jane Smith',
        'https://example.com/jane.png',
        'Lead Dev'
    ),
    (
        :'memberID',
        'test_hash',
        'member@example.com',
        true,
        'member1',
        '2024-01-01 00:00:00',
        null,
        'StartUp',
        'Bob Wilson',
        'https://example.com/bob.png',
        'Engineer'
    );

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    region_id,
    description,
    logo_url,
    og_image_url,
    banner_url,
    city,
    state,
    country_code,
    country_name,
    location,
    tags,
    website_url,
    bluesky_url,
    facebook_url,
    twitter_url,
    linkedin_url,
    github_url
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Kubernetes NYC',
    'abc1234',
    :'regionID',
    'New York Kubernetes meetup group for cloud native enthusiasts',
    'https://example.com/k8s-logo.png',
    'https://example.com/group-og.png',
    'https://example.com/k8s-banner.png',
    'New York',
    'NY',
    'US',
    'United States',
    ST_GeogFromText('POINT(-74.0060 40.7128)'),
    array['kubernetes', 'cloud-native', 'devops'],
    'https://k8s-nyc.example.com',
    'https://bsky.app/profile/k8snyc',
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
    (:'groupID', :'organizer1ID', 'admin', true, 1, '2024-01-01 00:00:00'),
    (:'groupID', :'organizer2ID', 'admin', true, 2, '2024-01-01 00:00:00');

-- Group Sponsors
insert into group_sponsor (
    group_sponsor_id,
    featured,
    group_id,
    logo_url,
    name,
    website_url
) values
    (
        :'sponsor1ID',
        true,
        :'groupID',
        'https://example.com/featured-sponsor.png',
        'Featured Sponsor',
        'https://featured-sponsor.example.com'
    ),
    (
        :'sponsor2ID',
        false,
        :'groupID',
        'https://example.com/hidden-sponsor.png',
        'Hidden Sponsor',
        'https://hidden-sponsor.example.com'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct group data as JSON
select is(
    get_group_full_by_slug(:'allianceID'::uuid, 'abc1234')::jsonb - '{created_at}'::text[],
    format(
        $json$
    {
        "active": true,
        "city": "New York",
        "name": "Kubernetes NYC",
        "slug": "abc1234",
        "tags": ["kubernetes", "cloud-native", "devops"],
        "state": "NY",
        "group_id": "%s",
        "latitude": 40.7128,
        "logo_url": "https://example.com/k8s-logo.png",
        "sponsors": [
            {
                "featured": true,
                "group_sponsor_id": "%s",
                "logo_url": "https://example.com/featured-sponsor.png",
                "name": "Featured Sponsor",
                "website_url": "https://featured-sponsor.example.com"
            },
            {
                "featured": false,
                "group_sponsor_id": "%s",
                "logo_url": "https://example.com/hidden-sponsor.png",
                "name": "Hidden Sponsor",
                "website_url": "https://hidden-sponsor.example.com"
            }
        ],
        "longitude": -74.006,
        "og_image_url": "https://example.com/group-og.png",
        "banner_url": "https://example.com/k8s-banner.png",
        "alliance": {
            "banner_mobile_url": "https://example.com/banner_mobile.png",
            "banner_url": "https://example.com/banner.png",
            "alliance_id": "%s",
            "coffee_meet_enabled": true,
            "display_name": "Cloud Native Seattle",
            "logo_url": "https://example.com/logo.png",
            "mentorship_enabled": true,
            "name": "cloud-native-seattle",
            "og_image_url": "https://example.com/alliance-og.png"
        },
        "github_url": "https://github.com/k8snyc",
        "organizers": [
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "%s",
                "username": "organizer1",
                "bio": "Group founder and speaker",
                "name": "John Doe",
                "photo_url": "https://example.com/john.png"
            },
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "%s",
                "username": "organizer2",
                "bio": "Alliance events coordinator",
                "name": "Jane Smith",
                "photo_url": "https://example.com/jane.png"
            }
        ],
        "description": "New York Kubernetes meetup group for cloud native enthusiasts",
        "region": {
            "region_id": "%s",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "bluesky_url": "https://bsky.app/profile/k8snyc",
        "twitter_url": "https://twitter.com/k8snyc",
        "website_url": "https://k8s-nyc.example.com",
        "coffee_meet_enabled": true,
        "country_code": "US",
        "country_name": "United States",
        "facebook_url": "https://facebook.com/k8snyc",
        "linkedin_url": "https://linkedin.com/company/k8snyc",
        "category": {
            "group_category_id": "%s",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "members_count": 3,
        "mentorship_enabled": true,
        "membership_approval_required": false
    }
        $json$,
        :'groupID',
        :'sponsor1ID',
        :'sponsor2ID',
        :'allianceID',
        :'organizer1ID',
        :'organizer2ID',
        :'regionID',
        :'groupCategoryID'
    )::jsonb,
    'Should return correct group data as JSON'
);

-- Should return null with non-existing group slug
select ok(
    get_group_full_by_slug(:'allianceID'::uuid, 'non-existing-group') is null,
    'Should return null with non-existing group slug'
);

-- Should resolve group by pretty slug
update "group" set slug_pretty = 'kubernetes-nyc' where group_id = :'groupID';
select is(
    get_group_full_by_slug(:'allianceID'::uuid, 'kubernetes-nyc')::jsonb->>'group_id',
    :'groupID',
    'Should resolve group by pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
