-- Start transaction and plan tests
begin;
select plan(4);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set event1ID '00000000-0000-0000-0000-000000000031'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000032'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000033'

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

-- Seed active group with location
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
    location
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
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326)
);

-- Seed inactive group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active
) values (
    :'groupInactiveID',
    'Inactive Group',
    'inactive-group',
    :'community1ID',
    :'category1ID',
    false
);

-- Seed published event with detailed information
insert into event (
    event_id,
    name,
    slug,
    description,
    event_kind_id,
    event_category_id,
    group_id,
    published,
    canceled,
    starts_at,
    ends_at,
    timezone,
    description_short,
    venue_name,
    venue_address,
    venue_city,
    logo_url
) values (
    :'event1ID',
    'Tech Conference 2024',
    'tech-conference-2024',
    'Annual technology conference with workshops and talks',
    'hybrid',
    :'eventCategory1ID',
    :'group1ID',
    true,
    false,
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
    'America/New_York',
    'Annual tech conference',
    'Convention Center',
    '123 Main St',
    'New York',
    'https://example.com/event-logo.png'
);

-- Seed unpublished event
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
    timezone
) values (
    :'eventUnpublishedID',
    'Unpublished Event',
    'unpublished-event',
    'This is an unpublished event',
    'virtual',
    :'eventCategory1ID',
    :'group1ID',
    false,
    '2024-07-15 09:00:00+00',
    'America/New_York'
);

-- Seed event with inactive group
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
    timezone
) values (
    :'eventInactiveGroupID',
    'Event with Inactive Group',
    'event-inactive-group',
    'Event with an inactive group',
    'virtual',
    :'eventCategory1ID',
    :'groupInactiveID',
    true,
    '2024-08-15 09:00:00+00',
    'America/New_York'
);

-- Test get_event_detailed function returns correct data
select is(
    get_event_detailed('00000000-0000-0000-0000-000000000031'::uuid)::jsonb,
    '{
        "canceled": false,
        "group_category_name": "Technology",
        "group_name": "Test Group",
        "group_slug": "test-group",
        "kind": "hybrid",
        "name": "Tech Conference 2024",
        "slug": "tech-conference-2024",
        "timezone": "America/New_York",
        "description_short": "Annual tech conference",
        "ends_at": 1718470800,
        "group_city": "New York",
        "group_country_code": "US",
        "group_country_name": "United States",
        "group_state": "NY",
        "latitude": 40.7128,
        "logo_url": "https://example.com/event-logo.png",
        "longitude": -74.006,
        "starts_at": 1718442000,
        "venue_address": "123 Main St",
        "venue_city": "New York",
        "venue_name": "Convention Center"
    }'::jsonb,
    'get_event_detailed should return correct detailed event data as JSON'
);

-- Test get_event_detailed with non-existent event ID
select ok(
    get_event_detailed('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_event_detailed with non-existent event ID should return null'
);

-- Test get_event_detailed with unpublished event
select ok(
    get_event_detailed('00000000-0000-0000-0000-000000000032'::uuid) is null,
    'get_event_detailed with unpublished event should return null'
);

-- Test get_event_detailed with inactive group
select ok(
    get_event_detailed('00000000-0000-0000-0000-000000000033'::uuid) is null,
    'get_event_detailed with inactive group should return null'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;