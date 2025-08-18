-- Start transaction and plan tests
begin;
select plan(2);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set event1ID '00000000-0000-0000-0000-000000000031'

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

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    city,
    state,
    country_code,
    country_name,
    logo_url
) values (
    :'group1ID',
    'Test Group',
    'test-group',
    :'community1ID',
    :'category1ID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'https://example.com/group-logo.png'
);

-- Seed published event
insert into event (
    event_id,
    name,
    slug,
    description,
    event_kind_id,
    event_category_id,
    group_id,
    published,
    starts_at,
    timezone,
    venue_city,
    logo_url
) values (
    :'event1ID',
    'Tech Conference 2024',
    'tech-conference-2024',
    'Annual technology conference with workshops and talks',
    'in-person',
    :'eventCategory1ID',
    :'group1ID',
    true,
    '2024-06-15 09:00:00+00',
    'America/New_York',
    'New York',
    'https://example.com/event-logo.png'
);


-- Test: get_event_summary function returns correct data
select is(
    get_event_summary('00000000-0000-0000-0000-000000000031'::uuid)::jsonb,
    '{
        "event_id": "00000000-0000-0000-0000-000000000031",
        "group_name": "Test Group",
        "group_slug": "test-group",
        "kind": "in-person",
        "name": "Tech Conference 2024",
        "slug": "tech-conference-2024",
        "timezone": "America/New_York",
        "group_city": "New York",
        "group_country_code": "US",
        "group_country_name": "United States",
        "group_state": "NY",
        "logo_url": "https://example.com/event-logo.png",
        "starts_at": 1718442000,
        "venue_city": "New York"
    }'::jsonb,
    'get_event_summary should return correct event summary data as JSON'
);

-- Test: get_event_summary with non-existent event ID
select ok(
    get_event_summary('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_event_summary with non-existent event ID should return null'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;