-- Start transaction and plan tests
begin;
select plan(2);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set groupCategory1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set event1ID '00000000-0000-0000-0000-000000000031'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000032'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000033'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set user3ID '00000000-0000-0000-0000-000000000043'
\set session1ID '00000000-0000-0000-0000-000000000051'
\set session2ID '00000000-0000-0000-0000-000000000052'

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
values (:'groupCategory1ID', 'Technology', :'community1ID');

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'community1ID');

-- Seed active group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    created_at
) values (
    :'group1ID',
    'Test Group',
    'test-group',
    :'community1ID',
    :'groupCategory1ID',
    true,
    '2024-03-01 10:00:00+00'
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
    :'groupCategory1ID',
    false
);

-- Seed users
insert into "user" (user_id, email, community_id, first_name, last_name, photo_url, company, title, facebook_url, linkedin_url, twitter_url, website_url)
values
    (:'user1ID', 'host@example.com', :'community1ID', 'John', 'Doe', 'https://example.com/john.png', 'Tech Corp', 'CTO', 'https://facebook.com/john', 'https://linkedin.com/in/john', 'https://twitter.com/john', 'https://johndoe.com'),
    (:'user2ID', 'organizer@example.com', :'community1ID', 'Jane', 'Smith', 'https://example.com/jane.png', 'Dev Inc', 'Lead Dev', 'https://facebook.com/jane', 'https://linkedin.com/in/jane', 'https://twitter.com/jane', 'https://janesmith.com'),
    (:'user3ID', 'speaker@example.com', :'community1ID', 'Alice', 'Johnson', 'https://example.com/alice.png', 'Cloud Co', 'Manager', null, 'https://linkedin.com/in/alice', null, null);

-- Seed published event with all fields
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
    published_at,
    canceled,
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
    recording_url,
    photos_urls,
    created_at
) values (
    :'event1ID',
    'Tech Conference 2024',
    'tech-conference-2024',
    'Annual technology conference with workshops and talks',
    'Annual tech conference',
    'America/New_York',
    :'eventCategory1ID',
    'hybrid',
    :'group1ID',
    true,
    '2024-05-01 12:00:00+00',
    false,
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
    'https://youtube.com/watch?v=123',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    '2024-04-01 10:00:00+00'
);

-- Add event host
insert into event_host (event_id, user_id)
values (:'event1ID', :'user1ID');

-- Add group organizer
insert into group_team (group_id, user_id, role, "order")
values (:'group1ID', :'user2ID', 'organizer', 1);

-- Add sessions
insert into session (
    session_id,
    event_id,
    name,
    description,
    session_kind_id,
    starts_at,
    ends_at,
    location,
    streaming_url,
    recording_url
) values (
    :'session1ID',
    :'event1ID',
    'Opening Keynote',
    'Welcome and opening remarks',
    'in-person',
    '2024-06-15 09:00:00+00',
    '2024-06-15 10:00:00+00',
    'Main Hall',
    'https://stream.example.com/session1',
    'https://youtube.com/watch?v=session1'
),
(
    :'session2ID',
    :'event1ID',
    'Tech Talk: AI in 2024',
    'Latest trends in artificial intelligence',
    'virtual',
    '2024-06-15 10:30:00+00',
    '2024-06-15 11:30:00+00',
    'Room A',
    null,
    null
);

-- Add session speaker
insert into session_speaker (session_id, user_id, featured)
values (:'session1ID', :'user3ID', true);

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

-- Test get_event_full function returns correct data
select is(
    get_event_full('00000000-0000-0000-0000-000000000031'::uuid)::jsonb,
    '{
        "canceled": false,
        "category_name": "Tech Talks",
        "created_at": 1711965600,
        "description": "Annual technology conference with workshops and talks",
        "event_id": "00000000-0000-0000-0000-000000000031",
        "kind": "hybrid",
        "name": "Tech Conference 2024",
        "published": true,
        "slug": "tech-conference-2024",
        "timezone": "America/New_York",
        "banner_url": "https://example.com/event-banner.png",
        "capacity": 500,
        "description_short": "Annual tech conference",
        "ends_at": 1718470800,
        "logo_url": "https://example.com/event-logo.png",
        "meetup_url": "https://meetup.com/event123",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "published_at": 1714564800,
        "recording_url": "https://youtube.com/watch?v=123",
        "registration_required": true,
        "starts_at": 1718442000,
        "streaming_url": "https://stream.example.com/live",
        "tags": ["technology", "conference", "workshops"],
        "venue_address": "123 Main St",
        "venue_city": "New York",
        "venue_name": "Convention Center",
        "venue_zip_code": "10001",
        "group": {
            "category": {
                "id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1709287200,
            "name": "Test Group",
            "slug": "test-group"
        },
        "hosts": [
            {
                "user_id": "00000000-0000-0000-0000-000000000041",
                "first_name": "John",
                "last_name": "Doe",
                "company": "Tech Corp",
                "facebook_url": "https://facebook.com/john",
                "linkedin_url": "https://linkedin.com/in/john",
                "photo_url": "https://example.com/john.png",
                "title": "CTO",
                "twitter_url": "https://twitter.com/john",
                "website_url": "https://johndoe.com"
            }
        ],
        "organizers": [
            {
                "user_id": "00000000-0000-0000-0000-000000000042",
                "first_name": "Jane",
                "last_name": "Smith",
                "company": "Dev Inc",
                "facebook_url": "https://facebook.com/jane",
                "linkedin_url": "https://linkedin.com/in/jane",
                "photo_url": "https://example.com/jane.png",
                "title": "Lead Dev",
                "twitter_url": "https://twitter.com/jane",
                "website_url": "https://janesmith.com"
            }
        ],
        "sessions": [
            {
                "description": "Welcome and opening remarks",
                "ends_at": 1718445600,
                "session_id": "00000000-0000-0000-0000-000000000051",
                "kind": "in-person",
                "name": "Opening Keynote",
                "starts_at": 1718442000,
                "location": "Main Hall",
                "recording_url": "https://youtube.com/watch?v=session1",
                "streaming_url": "https://stream.example.com/session1",
                "speakers": [
                    {
                        "user_id": "00000000-0000-0000-0000-000000000043",
                        "first_name": "Alice",
                        "last_name": "Johnson",
                        "company": "Cloud Co",
                        "linkedin_url": "https://linkedin.com/in/alice",
                        "photo_url": "https://example.com/alice.png",
                        "title": "Manager"
                    }
                ]
            },
            {
                "description": "Latest trends in artificial intelligence",
                "ends_at": 1718451000,
                "session_id": "00000000-0000-0000-0000-000000000052",
                "kind": "virtual",
                "name": "Tech Talk: AI in 2024",
                "starts_at": 1718447400,
                "location": "Room A",
                "speakers": []
            }
        ]
    }'::jsonb,
    'get_event_full should return complete event data with hosts, organizers, and sessions as JSON'
);

-- Test get_event_full with non-existent event ID
select ok(
    get_event_full('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_event_full with non-existent event ID should return null'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;
