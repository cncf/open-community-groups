-- Start transaction and plan tests
begin;
select plan(2);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set region1ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'

-- Seed community
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
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed users
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, name, photo_url, company, title, facebook_url, linkedin_url, twitter_url, website_url)
values
    (:'user1ID', 'organizer1@example.com', 'organizer1', false, 'test_hash'::bytea, :'community1ID', 'Alice Johnson', 'https://example.com/alice.png', 'Cloud Co', 'Manager', 'https://facebook.com/alice', 'https://linkedin.com/in/alice', 'https://twitter.com/alice', 'https://alice.com'),
    (:'user2ID', 'organizer2@example.com', 'organizer2', false, 'test_hash'::bytea, :'community1ID', 'Bob Wilson', 'https://example.com/bob.png', 'StartUp', 'Engineer', null, 'https://linkedin.com/in/bob', null, 'https://bob.com'),
    (:'user3ID', 'member1@example.com', 'member1', false, 'test_hash'::bytea, :'community1ID', 'Charlie Brown', null, null, null, null, null, null, null),
    (:'user4ID', 'member2@example.com', 'member2', false, 'test_hash'::bytea, :'community1ID', 'Diana Prince', null, null, null, null, null, null, null);

-- Seed active group with all fields including location
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
    :'group1ID',
    'Test Group',
    'test-group',
    :'community1ID',
    :'category1ID',
    :'region1ID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'A technology group focused on software development and innovation',
    'https://example.com/group-logo.png',
    'https://example.com/group-banner.png',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    array['technology', 'software', 'innovation'],
    'https://testgroup.com',
    'https://facebook.com/testgroup',
    'https://twitter.com/testgroup',
    'https://linkedin.com/company/testgroup',
    'https://github.com/testgroup',
    'https://instagram.com/testgroup',
    'https://youtube.com/@testgroup',
    'https://testgroup.slack.com',
    'https://flickr.com/testgroup',
    'https://wechat.com/testgroup',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    jsonb '[{"name": "Discord", "url": "https://discord.gg/testgroup"}, {"name": "Forum", "url": "https://forum.testgroup.com"}]',
    '2024-01-15 10:00:00+00'
);

-- Add group organizers
insert into group_team (group_id, user_id, role, "order")
values
    (:'group1ID', :'user1ID', 'organizer', 1),
    (:'group1ID', :'user2ID', 'organizer', 2);

-- Add group members
insert into group_member (group_id, user_id)
values
    (:'group1ID', :'user1ID'),
    (:'group1ID', :'user2ID'),
    (:'group1ID', :'user3ID'),
    (:'group1ID', :'user4ID');

-- Seed inactive group
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
    'Inactive Group',
    'inactive-group',
    :'community1ID',
    :'category1ID',
    false,
    '2024-02-15 10:00:00+00'
);

-- Test: get_group_full function returns correct data
select is(
    get_group_full('00000000-0000-0000-0000-000000000021'::uuid)::jsonb,
    '{
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "created_at": 1705312800,
        "group_id": "00000000-0000-0000-0000-000000000021",
        "members_count": 4,
        "name": "Test Group",
        "slug": "test-group",
        "banner_url": "https://example.com/group-banner.png",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description": "A technology group focused on software development and innovation",
        "extra_links": [{"name": "Discord", "url": "https://discord.gg/testgroup"}, {"name": "Forum", "url": "https://forum.testgroup.com"}],
        "facebook_url": "https://facebook.com/testgroup",
        "flickr_url": "https://flickr.com/testgroup",
        "github_url": "https://github.com/testgroup",
        "instagram_url": "https://instagram.com/testgroup",
        "latitude": 40.7128,
        "linkedin_url": "https://linkedin.com/company/testgroup",
        "logo_url": "https://example.com/group-logo.png",
        "longitude": -74.006,
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "slack_url": "https://testgroup.slack.com",
        "state": "NY",
        "tags": ["technology", "software", "innovation"],
        "twitter_url": "https://twitter.com/testgroup",
        "wechat_url": "https://wechat.com/testgroup",
        "website_url": "https://testgroup.com",
        "youtube_url": "https://youtube.com/@testgroup",
        "organizers": [
            {
                "user_id": "00000000-0000-0000-0000-000000000031",
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
                "name": "Bob Wilson",
                "company": "StartUp",
                "linkedin_url": "https://linkedin.com/in/bob",
                "photo_url": "https://example.com/bob.png",
                "title": "Engineer",
                "website_url": "https://bob.com"
            }
        ]
    }'::jsonb,
    'get_group_full should return complete group data with organizers and member count as JSON'
);

-- Test: get_group_full with non-existent group ID
select ok(
    get_group_full('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_group_full with non-existent group ID should return null'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
