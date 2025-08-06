-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set user3ID '00000000-0000-0000-0000-000000000043'

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
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Seed users
insert into "user" (user_id, email, community_id, first_name, last_name, company, title, photo_url, created_at)
values
    (:'user1ID', 'organizer1@example.com', :'community1ID', 'John', 'Doe', 'Tech Corp', 'CTO', 'https://example.com/john.png', '2024-01-01 00:00:00'),
    (:'user2ID', 'organizer2@example.com', :'community1ID', 'Jane', 'Smith', 'Dev Inc', 'Lead Dev', 'https://example.com/jane.png', '2024-01-01 00:00:00'),
    (:'user3ID', 'member@example.com', :'community1ID', 'Bob', 'Wilson', 'StartUp', 'Engineer', 'https://example.com/bob.png', '2024-01-01 00:00:00');

-- Seed group with all fields
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
    :'group1ID',
    'Kubernetes NYC',
    'kubernetes-nyc',
    :'community1ID',
    :'category1ID',
    :'region1ID',
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

-- Add group members
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user3ID', '2024-01-01 00:00:00');

-- Add group team (organizers)
insert into group_team (group_id, user_id, role, "order", created_at)
values
    (:'group1ID', :'user1ID', 'organizer', 1, '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', 'organizer', 2, '2024-01-01 00:00:00');

-- Test get_group function returns correct data
select is(
    get_group('00000000-0000-0000-0000-000000000001'::uuid, 'kubernetes-nyc')::jsonb - '{created_at}'::text[],
    '{
        "city": "New York",
        "name": "Kubernetes NYC",
        "slug": "kubernetes-nyc",
        "tags": ["kubernetes", "cloud-native", "devops"],
        "state": "NY",
        "latitude": 40.7128,
        "logo_url": "https://example.com/k8s-logo.png",
        "longitude": -74.006,
        "banner_url": "https://example.com/k8s-banner.png",
        "github_url": "https://github.com/k8snyc",
        "organizers": [
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "00000000-0000-0000-0000-000000000041",
                "last_name": "Doe",
                "photo_url": "https://example.com/john.png",
                "first_name": "John"
            },
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "00000000-0000-0000-0000-000000000042",
                "last_name": "Smith",
                "photo_url": "https://example.com/jane.png",
                "first_name": "Jane"
            }
        ],
        "description": "New York Kubernetes meetup group for cloud native enthusiasts",
        "region_name": "North America",
        "twitter_url": "https://twitter.com/k8snyc",
        "website_url": "https://k8s-nyc.example.com",
        "country_code": "US",
        "country_name": "United States",
        "facebook_url": "https://facebook.com/k8snyc",
        "linkedin_url": "https://linkedin.com/company/k8snyc",
        "category_name": "Technology",
        "members_count": 3
    }'::jsonb,
    'get_group should return correct group data as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;