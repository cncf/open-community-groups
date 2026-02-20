-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000021'
\set eventID '00000000-0000-0000-0000-000000000041'
\set groupID '00000000-0000-0000-0000-000000000031'
\set sponsor1ID '00000000-0000-0000-0000-000000000061'
\set sponsor2ID '00000000-0000-0000-0000-000000000062'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'
\set user3ID '00000000-0000-0000-0000-000000000053'
\set user4ID '00000000-0000-0000-0000-000000000054'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active, created_at)
values (:'groupID', 'Test Group', 'abc1234', :'communityID', :'categoryID', 'https://example.com/group-logo.png', true, '2025-02-11 10:00:00+00');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech Talks', 'tech-talks', :'communityID');

-- User
insert into "user" (user_id, auth_hash, email, username, created_at, bio, company, name, photo_url, title)
values
    (:'user1ID', 'test_hash', 'host1@example.com', 'host1', '2024-01-01 00:00:00', 'Conference opening speaker', 'Tech Corp', 'John Doe', 'https://example.com/john.png', 'CTO'),
    (:'user2ID', 'test_hash', 'host2@example.com', 'host2', '2024-01-01 00:00:00', 'Community host and emcee', 'Dev Inc', 'Jane Smith', 'https://example.com/jane.png', 'Lead Dev'),
    (:'user3ID', 'test_hash', 'organizer1@example.com', 'organizer1', '2024-01-01 00:00:00', 'Community programs lead', 'Cloud Co', 'Alice Johnson', 'https://example.com/alice.png', 'Manager'),
    (:'user4ID', 'test_hash', 'organizer2@example.com', 'organizer2', '2024-01-01 00:00:00', 'Operations and logistics manager', 'StartUp', 'Bob Wilson', 'https://example.com/bob.png', 'Engineer');

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
    photos_urls,
    capacity,
    registration_required,
    meeting_in_sync,
    meeting_join_url,
    meeting_recording_url,
    meeting_requested,
    meetup_url
) values (
    :'eventID',
    'Tech Conference 2024',
    'def5678',
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
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    500,
    true,
    true,
    'https://stream.example.com/live',
    'https://youtube.com/watch?v=123',
    false,
    'https://meetup.com/event123'
);

-- Event Host
insert into event_host (event_id, user_id, created_at)
values
    (:'eventID', :'user1ID', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', '2024-01-01 00:00:00');

-- Event Speakers
insert into event_speaker (event_id, user_id, featured, created_at)
values
    (:'eventID', :'user1ID', false, '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', true, '2024-01-01 00:00:00'),
    (:'eventID', :'user3ID', false, '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, checked_in, checked_in_at, created_at)
values
    (:'eventID', :'user1ID', true, '2024-01-01 00:00:00', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', false, null, '2024-01-01 00:00:00');

-- Group Team
insert into group_team (group_id, user_id, role, accepted, "order", created_at)
values
    (:'groupID', :'user3ID', 'organizer', true, 1, '2024-01-01 00:00:00'),
    (:'groupID', :'user4ID', 'organizer', true, 2, '2024-01-01 00:00:00');

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsor1ID', :'groupID', 'CloudInc', 'https://example.com/cloudinc.png', null),
    (:'sponsor2ID', :'groupID', 'TechCorp', 'https://example.com/techcorp.png', 'https://techcorp.com');

-- Event Sponsors (linking group sponsors to event)
insert into event_sponsor (event_id, group_sponsor_id, level)
values
    (:'eventID', :'sponsor1ID', 'Silver'),
    (:'eventID', :'sponsor2ID', 'Gold');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct event data as JSON
select is(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'def5678')::jsonb - '{created_at}'::text[],
    '{
        "kind": "hybrid",
        "name": "Tech Conference 2024",
        "slug": "def5678",
        "tags": ["technology", "conference", "workshops"],
        "community": {
            "banner_mobile_url": "https://example.com/banner_mobile.png",
            "banner_url": "https://example.com/banner.png",
            "community_id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Cloud Native Seattle",
            "logo_url": "https://example.com/logo.png",
            "name": "cloud-native-seattle"
        },
        "group": {
            "active": true,
            "name": "Test Group",
            "slug": "abc1234",
            "category": {
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "community_display_name": "Cloud Native Seattle",
            "community_name": "cloud-native-seattle",
            "created_at": 1739268000,
            "group_id": "00000000-0000-0000-0000-000000000031",
            "logo_url": "https://example.com/group-logo.png"
        },
        "hosts": [
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "00000000-0000-0000-0000-000000000052",
                "username": "host2",
                "bio": "Community host and emcee",
                "name": "Jane Smith",
                "photo_url": "https://example.com/jane.png"
            },
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "00000000-0000-0000-0000-000000000051",
                "username": "host1",
                "bio": "Conference opening speaker",
                "name": "John Doe",
                "photo_url": "https://example.com/john.png"
            }
        ],
        "speakers": [
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "00000000-0000-0000-0000-000000000052",
                "username": "host2",
                "bio": "Community host and emcee",
                "name": "Jane Smith",
                "featured": true,
                "photo_url": "https://example.com/jane.png"
            },
            {
                "title": "Manager",
                "company": "Cloud Co",
                "user_id": "00000000-0000-0000-0000-000000000053",
                "username": "organizer1",
                "bio": "Community programs lead",
                "name": "Alice Johnson",
                "featured": false,
                "photo_url": "https://example.com/alice.png"
            },
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "00000000-0000-0000-0000-000000000051",
                "username": "host1",
                "bio": "Conference opening speaker",
                "name": "John Doe",
                "featured": false,
                "photo_url": "https://example.com/john.png"
            }
        ],
        "legacy_hosts": [],
        "legacy_speakers": [],
        "ends_at": 1718470800,
        "canceled": false,
        "capacity": 500,
        "remaining_capacity": 498,
        "event_id": "00000000-0000-0000-0000-000000000041",
        "logo_url": "https://example.com/event-logo.png",
        "meeting_in_sync": true,
        "sessions": {},
        "timezone": "America/New_York",
        "published": true,
        "sponsors": [
            {
                "group_sponsor_id": "00000000-0000-0000-0000-000000000061",
                "level": "Silver",
                "logo_url": "https://example.com/cloudinc.png",
                "name": "CloudInc"
            },
            {
                "group_sponsor_id": "00000000-0000-0000-0000-000000000062",
                "level": "Gold",
                "logo_url": "https://example.com/techcorp.png",
                "name": "TechCorp",
                "website_url": "https://techcorp.com"
            }
        ],
        "starts_at": 1718442000,
        "banner_url": "https://example.com/event-banner.png",
        "cfs_labels": [],
        "meetup_url": "https://meetup.com/event123",
        "organizers": [
            {
                "title": "Manager",
                "company": "Cloud Co",
                "user_id": "00000000-0000-0000-0000-000000000053",
                "username": "organizer1",
                "bio": "Community programs lead",
                "name": "Alice Johnson",
                "photo_url": "https://example.com/alice.png"
            },
            {
                "title": "Engineer",
                "company": "StartUp",
                "user_id": "00000000-0000-0000-0000-000000000054",
                "username": "organizer2",
                "bio": "Operations and logistics manager",
                "name": "Bob Wilson",
                "photo_url": "https://example.com/bob.png"
            }
        ],
        "venue_city": "New York",
        "venue_name": "Convention Center",
        "description": "Annual technology conference with workshops and talks",
        "category_name": "Tech Talks",
        "meeting_join_url": "https://stream.example.com/live",
        "meeting_recording_url": "https://youtube.com/watch?v=123",
        "meeting_requested": false,
        "photos_urls": [
            "https://example.com/photo1.jpg",
            "https://example.com/photo2.jpg"
        ],
        "venue_address": "123 Main St",
        "venue_zip_code": "10001",
        "description_short": "Annual tech conference",
        "registration_required": true,
        "event_reminder_enabled": true
    }'::jsonb,
    'Should return correct event data as JSON'
);

-- Should return null with non-existing event slug
select ok(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'non-existing-event') is null,
    'Should return null with non-existing event slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
