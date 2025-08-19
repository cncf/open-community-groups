-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'
\set user3ID '00000000-0000-0000-0000-000000000053'
\set user4ID '00000000-0000-0000-0000-000000000054'

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
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active, created_at)
values (:'group1ID', 'Test Group', 'test-group', :'community1ID', :'category1ID', 'https://example.com/group-logo.png', true, '2025-02-11 10:00:00+00');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed users
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, name, photo_url, company, title, created_at)
values
    (:'user1ID', 'host1@example.com', 'host1', false, 'test_hash'::bytea, :'community1ID', 'John Doe', 'https://example.com/john.png', 'Tech Corp', 'CTO', '2024-01-01 00:00:00'),
    (:'user2ID', 'host2@example.com', 'host2', false, 'test_hash'::bytea, :'community1ID', 'Jane Smith', 'https://example.com/jane.png', 'Dev Inc', 'Lead Dev', '2024-01-01 00:00:00'),
    (:'user3ID', 'organizer1@example.com', 'organizer1', false, 'test_hash'::bytea, :'community1ID', 'Alice Johnson', 'https://example.com/alice.png', 'Cloud Co', 'Manager', '2024-01-01 00:00:00'),
    (:'user4ID', 'organizer2@example.com', 'organizer2', false, 'test_hash'::bytea, :'community1ID', 'Bob Wilson', 'https://example.com/bob.png', 'StartUp', 'Engineer', '2024-01-01 00:00:00');

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
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
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
insert into event_host (event_id, user_id, created_at)
values
    (:'event1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'event1ID', :'user2ID', '2024-01-01 00:00:00');

-- Add event attendees
insert into event_attendee (event_id, user_id, checked_in, created_at)
values
    (:'event1ID', :'user1ID', true, '2024-01-01 00:00:00'),
    (:'event1ID', :'user2ID', false, '2024-01-01 00:00:00');

-- Add group team members (organizers)
insert into group_team (group_id, user_id, role, "order", created_at)
values
    (:'group1ID', :'user3ID', 'organizer', 1, '2024-01-01 00:00:00'),
    (:'group1ID', :'user4ID', 'organizer', 2, '2024-01-01 00:00:00');

-- Test: get_event function returns correct data
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
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1739268000,
            "group_id": "00000000-0000-0000-0000-000000000031",
            "logo_url": "https://example.com/group-logo.png"
        },
        "hosts": [
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "00000000-0000-0000-0000-000000000052",
                "name": "Jane Smith",
                "photo_url": "https://example.com/jane.png"
            },
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "00000000-0000-0000-0000-000000000051",
                "name": "John Doe",
                "photo_url": "https://example.com/john.png"
            }
        ],
        "ends_at": 1718470800,
        "canceled": false,
        "capacity": 500,
        "event_id": "00000000-0000-0000-0000-000000000041",
        "logo_url": "https://example.com/event-logo.png",
        "sessions": [],
        "timezone": "America/New_York",
        "published": true,
        "starts_at": 1718442000,
        "banner_url": "https://example.com/event-banner.png",
        "meetup_url": "https://meetup.com/event123",
        "organizers": [
            {
                "title": "Manager",
                "company": "Cloud Co",
                "user_id": "00000000-0000-0000-0000-000000000053",
                "name": "Alice Johnson",
                "photo_url": "https://example.com/alice.png"
            },
            {
                "title": "Engineer",
                "company": "StartUp",
                "user_id": "00000000-0000-0000-0000-000000000054",
                "name": "Bob Wilson",
                "photo_url": "https://example.com/bob.png"
            }
        ],
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

-- Test: get_event with non-existing event slug
select ok(
    get_event('00000000-0000-0000-0000-000000000001'::uuid, 'test-group', 'non-existing-event') is null,
    'get_event with non-existing event slug should return null'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;