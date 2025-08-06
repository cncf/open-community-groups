-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'

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
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID', 'https://example.com/group-logo.png');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed users
insert into "user" (user_id, email, community_id, first_name, last_name, photo_url)
values
    (:'user1ID', 'host1@example.com', :'community1ID', 'John', 'Doe', 'https://example.com/john.png'),
    (:'user2ID', 'host2@example.com', :'community1ID', 'Jane', 'Smith', 'https://example.com/jane.png');

-- Seed event with all fields
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    timezone,
    timezone_abbr,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    tags,
    venue_name,
    venue_address,
    venue_city,
    venue_zip_code,
    logo_url,
    banner_url,
    capacity,
    registration_required,
    meetup_url,
    streaming_url,
    recording_url
) values (
    :'event1ID',
    'Tech Conference 2024',
    'tech-conference-2024',
    'Annual technology conference with workshops and talks',
    'Annual tech conference',
    'America/New_York',
    'EST',
    :'eventCategory1ID',
    'hybrid',
    :'group1ID',
    true,
    '2024-06-15 09:00:00',
    '2024-06-15 18:00:00',
    array['technology', 'conference', 'workshops'],
    'Convention Center',
    '123 Main St',
    'New York',
    '10001',
    'https://example.com/event-logo.png',
    'https://example.com/event-banner.png',
    500,
    true,
    'https://meetup.com/event123',
    'https://stream.example.com/live',
    'https://youtube.com/watch?v=123'
);

-- Add event hosts
insert into event_host (event_id, user_id)
values
    (:'event1ID', :'user1ID'),
    (:'event1ID', :'user2ID');

-- Add event attendees
insert into event_attendee (event_id, user_id, checked_in)
values
    (:'event1ID', :'user1ID', true),
    (:'event1ID', :'user2ID', false);

-- Test get_event function returns correct data
select is(
    get_event('00000000-0000-0000-0000-000000000001'::uuid, 'test-group', 'tech-conference-2024')::jsonb - '{created_at}'::text[],
    '{
        "kind": "hybrid",
        "name": "Tech Conference 2024",
        "slug": "tech-conference-2024",
        "tags": ["technology", "conference", "workshops"],
        "group": {
            "name": "Test Group",
            "slug": "test-group",
            "category_name": "Technology"
        },
        "hosts": [
            {
                "user_id": "00000000-0000-0000-0000-000000000052",
                "last_name": "Smith",
                "photo_url": "https://example.com/jane.png",
                "first_name": "Jane"
            },
            {
                "user_id": "00000000-0000-0000-0000-000000000051",
                "last_name": "Doe",
                "photo_url": "https://example.com/john.png",
                "first_name": "John"
            }
        ],
        "ends_at": 1718467200,
        "canceled": false,
        "capacity": 500,
        "event_id": "00000000-0000-0000-0000-000000000041",
        "logo_url": "https://example.com/event-logo.png",
        "sessions": [],
        "timezone": "America/New_York",
        "published": true,
        "starts_at": 1718434800,
        "banner_url": "https://example.com/event-banner.png",
        "meetup_url": "https://meetup.com/event123",
        "organizers": [],
        "venue_city": "New York",
        "venue_name": "Convention Center",
        "description": "Annual technology conference with workshops and talks",
        "category_name": "Tech Talks",
        "recording_url": "https://youtube.com/watch?v=123",
        "streaming_url": "https://stream.example.com/live",
        "venue_address": "123 Main St",
        "venue_zip_code": "10001",
        "description_short": "Annual tech conference",
        "registration_required": true
    }'::jsonb,
    'get_event should return correct event data as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;