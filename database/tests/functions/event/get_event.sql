-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set eventID '00000000-0000-0000-0000-000000000041'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'
\set user3ID '00000000-0000-0000-0000-000000000053'
\set user4ID '00000000-0000-0000-0000-000000000054'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
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
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Test Community Title',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active, created_at)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'https://example.com/group-logo.png', true, '2025-02-11 10:00:00+00');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech Talks', 'tech-talks', :'communityID');

-- User
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, name, photo_url, company, title, created_at)
values
    (:'user1ID', 'host1@example.com', 'host1', false, 'test_hash', :'communityID', 'John Doe', 'https://example.com/john.png', 'Tech Corp', 'CTO', '2024-01-01 00:00:00'),
    (:'user2ID', 'host2@example.com', 'host2', false, 'test_hash', :'communityID', 'Jane Smith', 'https://example.com/jane.png', 'Dev Inc', 'Lead Dev', '2024-01-01 00:00:00'),
    (:'user3ID', 'organizer1@example.com', 'organizer1', false, 'test_hash', :'communityID', 'Alice Johnson', 'https://example.com/alice.png', 'Cloud Co', 'Manager', '2024-01-01 00:00:00'),
    (:'user4ID', 'organizer2@example.com', 'organizer2', false, 'test_hash', :'communityID', 'Bob Wilson', 'https://example.com/bob.png', 'StartUp', 'Engineer', '2024-01-01 00:00:00');

-- Event
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
    :'eventID',
    'Tech Conference 2024',
    'tech-conference-2024',
    'Annual technology conference with workshops and talks',
    'Annual tech conference',
    'America/New_York',
    :'eventCategoryID',
    'hybrid',
    :'groupID',
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

-- Event Host
insert into event_host (event_id, user_id, created_at)
values
    (:'eventID', :'user1ID', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, checked_in, created_at)
values
    (:'eventID', :'user1ID', true, '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', false, '2024-01-01 00:00:00');

-- Group Team
insert into group_team (group_id, user_id, role, "order", created_at)
values
    (:'groupID', :'user3ID', 'organizer', 1, '2024-01-01 00:00:00'),
    (:'groupID', :'user4ID', 'organizer', 2, '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_event should return correct event JSON
select is(
    get_event(:'communityID'::uuid, 'test-group', 'tech-conference-2024')::jsonb - '{created_at}'::text[],
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

-- Test: get_event with non-existing event slug should return null
select ok(
    get_event(:'communityID'::uuid, 'test-group', 'non-existing-event') is null,
    'get_event with non-existing event slug should return null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
