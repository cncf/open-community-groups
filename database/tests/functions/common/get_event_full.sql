-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000033'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000032'
\set groupID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set session1ID '00000000-0000-0000-0000-000000000051'
\set session2ID '00000000-0000-0000-0000-000000000052'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set user3ID '00000000-0000-0000-0000-000000000043'

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
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech Talks', 'tech-talks', :'communityID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active,
    created_at,
    location
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'seattle-kubernetes-meetup',
    :'communityID',
    :'groupCategoryID',
    true,
    '2024-03-01 10:00:00+00',
    ST_SetSRID(ST_MakePoint(-73.935242, 40.730610), 4326)  -- New York coordinates
);

-- Group (inactive)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active
) values (
    :'groupInactiveID',
    'Inactive DevOps Group',
    'inactive-devops-group',
    :'communityID',
    :'groupCategoryID',
    false
);

-- User
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, name, photo_url, company, title, facebook_url, linkedin_url, twitter_url, website_url)
values
    (:'user1ID', 'host@seattle.cloudnative.org', 'sarah-host', false, 'test_hash', :'communityID', 'Sarah Chen', 'https://example.com/sarah.png', 'Microsoft', 'Principal Engineer', 'https://facebook.com/sarahchen', 'https://linkedin.com/in/sarahchen', 'https://twitter.com/sarahchen', 'https://sarahchen.dev'),
    (:'user2ID', 'organizer@seattle.cloudnative.org', 'mike-organizer', false, 'test_hash', :'communityID', 'Mike Rodriguez', 'https://example.com/mike.png', 'AWS', 'Solutions Architect', 'https://facebook.com/mikerod', 'https://linkedin.com/in/mikerod', 'https://twitter.com/mikerod', 'https://mikerodriguez.io'),
    (:'user3ID', 'speaker@seattle.cloudnative.org', 'alex-speaker', false, 'test_hash', :'communityID', 'Alex Thompson', 'https://example.com/alex.png', 'Google', 'Staff Engineer', null, 'https://linkedin.com/in/alexthompson', null, null);

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
    :'eventID',
    'KubeCon Seattle 2024',
    'kubecon-seattle-2024',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts from across the cloud native ecosystem',
    'Annual Kubernetes conference',
    'America/New_York',
    :'eventCategoryID',
    'hybrid',
    :'groupID',
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

-- Event Host
insert into event_host (event_id, user_id)
values (:'eventID', :'user1ID');

-- Group Team
insert into group_team (group_id, user_id, role, "order")
values (:'groupID', :'user2ID', 'organizer', 1);

-- Session
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
    :'eventID',
    'Opening Keynote: The Future of Cloud Native',
    'Welcome keynote exploring the evolving landscape of cloud native technologies',
    'in-person',
    '2024-06-15 09:00:00+00',
    '2024-06-15 10:00:00+00',
    'Main Hall',
    'https://stream.example.com/session1',
    'https://youtube.com/watch?v=session1'
),
(
    :'session2ID',
    :'eventID',
    'Workshop: Kubernetes Security Best Practices',
    'Hands-on workshop covering security fundamentals for Kubernetes deployments',
    'virtual',
    '2024-06-15 10:30:00+00',
    '2024-06-15 11:30:00+00',
    'Room A',
    null,
    null
);

-- Session Speaker
insert into session_speaker (session_id, user_id, featured)
values (:'session1ID', :'user3ID', true);

-- Sponsors
insert into event_sponsor (event_id, name, logo_url, level, website_url)
values
    (:'eventID', 'CloudInc', 'https://example.com/cloudinc.png', 'Silver', null),
    (:'eventID', 'TechCorp', 'https://example.com/techcorp.png', 'Gold', 'https://techcorp.com');

-- Event (unpublished)
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
    'Draft Workshop',
    'draft-workshop',
    'A draft workshop that is not yet published',
    'virtual',
    :'eventCategoryID',
    :'groupID',
    false,
    '2024-07-15 09:00:00+00',
    'America/New_York'
);

-- Event (inactive group)
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
    'Legacy Event',
    'legacy-event',
    'An event from an inactive group that should not appear in normal listings',
    'virtual',
    :'eventCategoryID',
    :'groupInactiveID',
    true,
    '2024-08-15 09:00:00+00',
    'America/New_York'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_event_full should return complete event JSON
select is(
    get_event_full('00000000-0000-0000-0000-000000000031'::uuid)::jsonb,
    '{
        "canceled": false,
        "category_name": "Tech Talks",
        "created_at": 1711965600,
        "description": "Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts from across the cloud native ecosystem",
        "event_id": "00000000-0000-0000-0000-000000000031",
        "kind": "hybrid",
        "name": "KubeCon Seattle 2024",
        "published": true,
        "slug": "kubecon-seattle-2024",
        "timezone": "America/New_York",
        "banner_url": "https://example.com/event-banner.png",
        "capacity": 500,
        "description_short": "Annual Kubernetes conference",
        "ends_at": 1718470800,
        "latitude": 40.73061,
        "logo_url": "https://example.com/event-logo.png",
        "longitude": -73.935242,
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
                "group_category_id": "00000000-0000-0000-0000-000000000011",
                "name": "Technology",
                "normalized_name": "technology"
            },
            "created_at": 1709287200,
            "group_id": "00000000-0000-0000-0000-000000000021",
            "name": "Seattle Kubernetes Meetup",
            "slug": "seattle-kubernetes-meetup"
        },
        "hosts": [
            {
                "user_id": "00000000-0000-0000-0000-000000000041",
                "name": "Sarah Chen",
                "company": "Microsoft",
                "facebook_url": "https://facebook.com/sarahchen",
                "linkedin_url": "https://linkedin.com/in/sarahchen",
                "photo_url": "https://example.com/sarah.png",
                "title": "Principal Engineer",
                "twitter_url": "https://twitter.com/sarahchen",
                "website_url": "https://sarahchen.dev"
            }
        ],
        "organizers": [
            {
                "user_id": "00000000-0000-0000-0000-000000000042",
                "name": "Mike Rodriguez",
                "company": "AWS",
                "facebook_url": "https://facebook.com/mikerod",
                "linkedin_url": "https://linkedin.com/in/mikerod",
                "photo_url": "https://example.com/mike.png",
                "title": "Solutions Architect",
                "twitter_url": "https://twitter.com/mikerod",
                "website_url": "https://mikerodriguez.io"
            }
        ],
        "sessions": [
            {
                "description": "Welcome keynote exploring the evolving landscape of cloud native technologies",
                "ends_at": 1718445600,
                "session_id": "00000000-0000-0000-0000-000000000051",
                "kind": "in-person",
                "name": "Opening Keynote: The Future of Cloud Native",
                "starts_at": 1718442000,
                "location": "Main Hall",
                "recording_url": "https://youtube.com/watch?v=session1",
                "streaming_url": "https://stream.example.com/session1",
                "speakers": [
                    {
                        "user_id": "00000000-0000-0000-0000-000000000043",
                        "name": "Alex Thompson",
                        "company": "Google",
                        "linkedin_url": "https://linkedin.com/in/alexthompson",
                        "photo_url": "https://example.com/alex.png",
                        "title": "Staff Engineer"
                    }
                ]
            },
            {
                "description": "Hands-on workshop covering security fundamentals for Kubernetes deployments",
                "ends_at": 1718451000,
                "session_id": "00000000-0000-0000-0000-000000000052",
                "kind": "virtual",
                "name": "Workshop: Kubernetes Security Best Practices",
                "starts_at": 1718447400,
                "location": "Room A",
                "speakers": []
            }
        ],
        "sponsors": [
            {
                "level": "Silver",
                "logo_url": "https://example.com/cloudinc.png",
                "name": "CloudInc"
            },
            {
                "level": "Gold",
                "logo_url": "https://example.com/techcorp.png",
                "name": "TechCorp",
                "website_url": "https://techcorp.com"
            }
        ]
    }'::jsonb,
    'get_event_full should return complete event data with hosts, organizers, and sessions as JSON'
);

-- Test: get_event_full with non-existent event should return null

select ok(
    get_event_full('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_event_full with non-existent event ID should return null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
