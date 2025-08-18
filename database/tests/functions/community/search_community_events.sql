-- Start transaction and plan tests
begin;
select plan(3);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'

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

-- Seed group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name, logo_url, location)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID',
        'San Francisco', 'CA', 'US', 'United States', 'https://example.com/group-logo.png',
        ST_GeogFromText('POINT(-122.4194 37.7749)'));

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed events
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    tags,
    venue_city,
    venue_name,
    venue_address,
    logo_url
) values
    (:'event1ID', 'Kubernetes Workshop', 'kubernetes-workshop', 'Learn Kubernetes', 'K8s intro workshop', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2026-02-01 10:00:00+00', '2026-02-01 12:00:00+00', array['kubernetes', 'cloud'],
     'San Francisco', 'Tech Hub', '123 Market St', 'https://example.com/k8s-workshop.png'),
    (:'event2ID', 'Docker Training', 'docker-training', 'Docker fundamentals', 'Docker basics', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-02 10:00:00+00', '2026-02-02 13:00:00+00', array['docker', 'containers'],
     'New York', 'Online', null, 'https://example.com/docker-training.png'),
    (:'event3ID', 'Cloud Summit', 'cloud-summit', 'Annual cloud conference', 'Cloud conf 2026', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', true,
     '2026-02-03 10:00:00+00', '2026-02-03 17:00:00+00', array['cloud', 'aws'],
     'London', 'Convention Center', '456 Oxford St', 'https://example.com/cloud-summit.png');

-- Test: search without filters returns all events with full JSON verification
select is(
    (select events from search_community_events(:'community1ID'::uuid, '{}'::jsonb))::jsonb,
    '[
        {
            "canceled": false,
            "event_id": "00000000-0000-0000-0000-000000000041",
            "kind": "in-person",
            "name": "Kubernetes Workshop",
            "slug": "kubernetes-workshop",
            "timezone": "UTC",
            "description_short": "K8s intro workshop",
            "ends_at": 1769947200,
            "group_category_name": "Technology",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "group_state": "CA",
            "latitude": 37.7749,
            "logo_url": "https://example.com/k8s-workshop.png",
            "longitude": -122.4194,
            "starts_at": 1769940000,
            "venue_city": "San Francisco",
            "venue_name": "Tech Hub",
            "venue_address": "123 Market St"
        },
        {
            "canceled": false,
            "event_id": "00000000-0000-0000-0000-000000000042",
            "kind": "virtual",
            "name": "Docker Training",
            "slug": "docker-training",
            "timezone": "UTC",
            "description_short": "Docker basics",
            "ends_at": 1770037200,
            "group_category_name": "Technology",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "group_state": "CA",
            "latitude": 37.7749,
            "logo_url": "https://example.com/docker-training.png",
            "longitude": -122.4194,
            "starts_at": 1770026400,
            "venue_city": "New York",
            "venue_name": "Online"
        },
        {
            "canceled": false,
            "event_id": "00000000-0000-0000-0000-000000000043",
            "kind": "hybrid",
            "name": "Cloud Summit",
            "slug": "cloud-summit",
            "timezone": "UTC",
            "description_short": "Cloud conf 2026",
            "ends_at": 1770138000,
            "group_category_name": "Technology",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "group_state": "CA",
            "latitude": 37.7749,
            "logo_url": "https://example.com/cloud-summit.png",
            "longitude": -122.4194,
            "starts_at": 1770112800,
            "venue_city": "London",
            "venue_name": "Convention Center",
            "venue_address": "456 Oxford St"
        }
    ]'::jsonb,
    'search_community_events without filters should return all published events with correct JSON structure'
);

-- Test: total count
select is(
    (select total from search_community_events(:'community1ID'::uuid, '{}'::jsonb)),
    3::bigint,
    'search_community_events should return correct total count'
);

-- Test: search with non-existing community
select is(
    (select total from search_community_events('00000000-0000-0000-0000-999999999999'::uuid, '{}'::jsonb)),
    0::bigint,
    'search_community_events with non-existing community should return zero total'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
