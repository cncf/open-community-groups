-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'
\set user3ID '00000000-0000-0000-0000-000000000022'
\set invalidUserID '99999999-9999-9999-9999-999999999999'

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

-- Users
insert into "user" (user_id, community_id, email, username, auth_hash, name) values
    (:'user1ID', :'communityID', 'host1@example.com', 'host1', 'hash1', 'Host One'),
    (:'user2ID', :'communityID', 'host2@example.com', 'host2', 'hash2', 'Host Two'),
    (:'user3ID', :'communityID', 'speaker1@example.com', 'speaker1', 'hash3', 'Speaker One');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'communityID',
    'Kubernetes Study Group',
    'kubernetes-study-group',
    'A study group focused on Kubernetes best practices and implementation',
    :'groupCategoryID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- add_event function creates event with required fields only
select is(
    (select (get_event_full(
        add_event(
            :'groupID'::uuid,
            '{"name": "Kubernetes Fundamentals Workshop", "slug": "k8s-fundamentals-workshop", "description": "Learn the basics of Kubernetes deployment and management", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
        )
    )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group')),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Learn the basics of Kubernetes deployment and management",
        "hosts": [],
        "kind": "in-person",
        "name": "Kubernetes Fundamentals Workshop",
        "published": false,
        "sessions": [],
        "slug": "k8s-fundamentals-workshop",
        "timezone": "America/New_York"
    }'::jsonb,
    'add_event should create event with minimal required fields and return expected structure'
);

-- add_event function creates event with all fields including hosts, sponsors, and sessions
with new_event as (
    select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{
            "name": "CloudNativeCon Seattle 2025",
            "slug": "cloudnativecon-seattle-2025",
            "description": "Premier conference for cloud native technologies and community collaboration",
            "timezone": "America/Los_Angeles",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "hybrid",
            "banner_url": "https://example.com/banner.jpg",
            "capacity": 100,
            "description_short": "Short description",
            "starts_at": "2025-01-01T10:00:00",
            "ends_at": "2025-01-01T12:00:00",
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
            "venue_zip_code": "94105",
            "hosts": ["00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021"],
            "sponsors": [
                {
                    "name": "TechCorp",
                    "logo_url": "https://example.com/techcorp.png",
                    "level": "Gold",
                    "website_url": "https://techcorp.com"
                },
                {
                    "name": "CloudInc",
                    "logo_url": "https://example.com/cloudinc.png",
                    "level": "Silver"
                }
            ],
            "sessions": [
                {
                    "name": "Opening Keynote",
                    "description": "Welcome and introduction to the conference",
                    "starts_at": "2025-01-01T10:00:00",
                    "ends_at": "2025-01-01T10:45:00",
                    "kind": "in-person",
                    "location": "Main Hall",
                    "speakers": ["00000000-0000-0000-0000-000000000022"]
                },
                {
                    "name": "Kubernetes Best Practices",
                    "description": "Deep dive into Kubernetes best practices",
                    "starts_at": "2025-01-01T11:00:00",
                    "ends_at": "2025-01-01T11:45:00",
                    "kind": "virtual",
                    "streaming_url": "https://youtube.com/live/session2",
                    "speakers": ["00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021"]
                }
            ]
        }'::jsonb
    ) as event_id
)
select is(
    (select get_event_full(event_id)::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'sessions' from new_event)
        -- Add back sessions without session_ids (which are random)
        || jsonb_build_object('sessions',
            (select jsonb_agg(session - 'session_id' order by session->>'name')
             from jsonb_array_elements((
                select get_event_full(event_id)::jsonb->'sessions' from new_event
             )) as session)
        ),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Premier conference for cloud native technologies and community collaboration",
        "hosts": [
            {"name": "Host One", "user_id": "00000000-0000-0000-0000-000000000020"},
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021"}
        ],
        "kind": "hybrid",
        "name": "CloudNativeCon Seattle 2025",
        "published": false,
        "slug": "cloudnativecon-seattle-2025",
        "timezone": "America/Los_Angeles",
        "banner_url": "https://example.com/banner.jpg",
        "capacity": 100,
        "description_short": "Short description",
        "starts_at": 1735754400,
        "ends_at": 1735761600,
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
        "venue_zip_code": "94105",
        "sessions": [
            {
                "name": "Kubernetes Best Practices",
                "description": "Deep dive into Kubernetes best practices",
                "starts_at": 1735758000,
                "ends_at": 1735760700,
                "kind": "virtual",
                "streaming_url": "https://youtube.com/live/session2",
                "speakers": [
                    {"name": "Host One", "user_id": "00000000-0000-0000-0000-000000000020"},
                    {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021"}
                ]
            },
            {
                "name": "Opening Keynote",
                "description": "Welcome and introduction to the conference",
                "starts_at": 1735754400,
                "ends_at": 1735757100,
                "kind": "in-person",
                "location": "Main Hall",
                "speakers": [
                    {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022"}
                ]
            }
        ]
    }'::jsonb,
    'add_event should create event with all fields including hosts, sponsors, and sessions'
);

-- add_event throws error for invalid host user_id
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Test Event", "slug": "test-event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "hosts": ["99999999-9999-9999-9999-999999999999"]}'::jsonb
    )$$,
    'P0001',
    'host user 99999999-9999-9999-9999-999999999999 not found in community',
    'add_event should throw error when host user_id does not exist in community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
