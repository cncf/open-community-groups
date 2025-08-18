-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set category1ID '00000000-0000-0000-0000-000000000011'

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

-- Seed event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'category1ID', 'Conference', 'conference', :'community1ID');

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'community1ID');

-- Seed group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'community1ID',
    'Test Group',
    'test-group',
    'A test group',
    '00000000-0000-0000-0000-000000000010'
);

-- Test: add_event function creates event with required fields only
select is(
    (select (get_event_full(
        add_event(
            '00000000-0000-0000-0000-000000000002'::uuid,
            '{"name": "Simple Test Event", "slug": "simple-test-event", "description": "A simple test event", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
        )
    )::jsonb - 'created_at' - 'event_id' - 'hosts' - 'organizers' - 'sessions' - 'group')),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "A simple test event",
        "kind": "in-person",
        "name": "Simple Test Event",
        "published": false,
        "slug": "simple-test-event",
        "timezone": "America/New_York"
    }'::jsonb,
    'add_event should create event with minimal required fields and return expected structure'
);

-- Test: add_event function creates event with all fields
select is(
    (select (get_event_full(
        add_event(
            '00000000-0000-0000-0000-000000000002'::uuid,
            '{
                "name": "Full Test Event",
                "slug": "full-test-event",
                "description": "A fully populated test event",
                "timezone": "America/Los_Angeles",
                "category_id": "00000000-0000-0000-0000-000000000011",
                "kind_id": "hybrid",
                "banner_url": "https://example.com/banner.jpg",
                "capacity": 100,
                "description_short": "Short description",
                "starts_at": "2025-01-01T10:00:00Z",
                "ends_at": "2025-01-01T12:00:00Z",
                "logo_url": "https://example.com/logo.png",
                "meetup_url": "https://meetup.com/event",
                "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
                "recording_url": "https://youtube.com/recording",
                "registration_required": true,
                "streaming_url": "https://youtube.com/live",
                "tags": ["technology", "conference", "networking"],
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_name": "Tech Center",
                "venue_zip_code": "94105"
            }'::jsonb
        )
    )::jsonb - 'created_at' - 'event_id' - 'hosts' - 'organizers' - 'sessions' - 'group')),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "A fully populated test event",
        "kind": "hybrid",
        "name": "Full Test Event",
        "published": false,
        "slug": "full-test-event",
        "timezone": "America/Los_Angeles",
        "banner_url": "https://example.com/banner.jpg",
        "capacity": 100,
        "description_short": "Short description",
        "starts_at": 1735725600,
        "ends_at": 1735732800,
        "logo_url": "https://example.com/logo.png",
        "meetup_url": "https://meetup.com/event",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "recording_url": "https://youtube.com/recording",
        "registration_required": true,
        "streaming_url": "https://youtube.com/live",
        "tags": ["technology", "conference", "networking"],
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_name": "Tech Center",
        "venue_zip_code": "94105"
    }'::jsonb,
    'add_event should create event with all fields and return expected structure'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;