-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

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
\set sponsor1ID '00000000-0000-0000-0000-000000000061'
\set sponsor2ID '00000000-0000-0000-0000-000000000062'

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

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsor1ID', :'groupID', 'TechCorp', 'https://example.com/techcorp.png', 'https://techcorp.com'),
    (:'sponsor2ID', :'groupID', 'CloudInc', 'https://example.com/cloudinc.png', null);


-- ============================================================================
-- TESTS
-- ============================================================================

-- add_event function creates event with required fields only
select is(
    (select (
        get_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            add_event(
                :'groupID'::uuid,
                '{"name": "Kubernetes Fundamentals Workshop", "slug": "k8s-fundamentals-workshop", "description": "Learn the basics of Kubernetes deployment and management", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
            )
        )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers'
    )),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Learn the basics of Kubernetes deployment and management",
        "hosts": [],
        "speakers": [],
        "kind": "in-person",
        "name": "Kubernetes Fundamentals Workshop",
        "published": false,
        "sponsors": [],
        "sessions": {},
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
            "meeting_hosts": ["host1@example.com", "host2@example.com"],
            "meeting_join_url": "https://youtube.com/live",
            "meeting_recording_url": "https://youtube.com/recording",
            "meetup_url": "https://meetup.com/event",
            "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
            "registration_required": true,
            "tags": ["technology", "conference", "networking"],
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_name": "Tech Center",
            "venue_zip_code": "94105",
            "hosts": ["00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021"],
            "speakers": [
                {"user_id": "00000000-0000-0000-0000-000000000021", "featured": true},
                {"user_id": "00000000-0000-0000-0000-000000000022", "featured": false}
            ],
            "sessions": [
                {
                    "name": "Opening Keynote",
                    "description": "Welcome and introduction to the conference",
                    "starts_at": "2025-01-01T10:00:00",
                    "ends_at": "2025-01-01T10:45:00",
                    "kind": "in-person",
                    "location": "Main Hall",
                    "speakers": [{"user_id": "00000000-0000-0000-0000-000000000022", "featured": true}]
                },
                {
                    "name": "Kubernetes Best Practices",
                    "description": "Deep dive into Kubernetes best practices",
                    "starts_at": "2025-01-01T11:00:00",
                    "ends_at": "2025-01-01T11:45:00",
                    "kind": "virtual",
                    "meeting_hosts": ["session-host@example.com"],
                    "meeting_join_url": "https://youtube.com/live/session2",
                    "speakers": [
                        {"user_id": "00000000-0000-0000-0000-000000000020", "featured": false},
                        {"user_id": "00000000-0000-0000-0000-000000000021", "featured": true}
                    ]
                }
            ],
            "sponsors": [
                {"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "level": "Gold"},
                {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Silver"}
            ]
        }'::jsonb
    ) as event_id
)
select event_id from new_event \gset

-- Check event fields except sessions
select is(
    (select get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'event_id'::uuid
    )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions'),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Premier conference for cloud native technologies and community collaboration",
        "hosts": [
            {"name": "Host One", "user_id": "00000000-0000-0000-0000-000000000020", "username": "host1"},
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2"}
        ],
        "speakers": [
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2", "featured": true},
            {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1", "featured": false}
        ],
        "kind": "hybrid",
        "name": "CloudNativeCon Seattle 2025",
        "published": false,
        "slug": "cloudnativecon-seattle-2025",
        "timezone": "America/Los_Angeles",
        "banner_url": "https://example.com/banner.jpg",
        "capacity": 100,
        "remaining_capacity": 100,
        "description_short": "Short description",
        "starts_at": 1735754400,
        "ends_at": 1735761600,
        "logo_url": "https://example.com/logo.png",
        "meeting_hosts": ["host1@example.com", "host2@example.com"],
        "meeting_join_url": "https://youtube.com/live",
        "meeting_recording_url": "https://youtube.com/recording",
        "meetup_url": "https://meetup.com/event",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "registration_required": true,
        "tags": ["technology", "conference", "networking"],
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_name": "Tech Center",
        "venue_zip_code": "94105",
        "sponsors": [
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Silver", "logo_url": "https://example.com/cloudinc.png", "name": "CloudInc"},
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "level": "Gold", "logo_url": "https://example.com/techcorp.png", "name": "TechCorp", "website_url": "https://techcorp.com"}
        ]
    }'::jsonb,
    'add_event should create event with all fields (excluding sessions)'
);


-- Sessions assertions: contents ignoring session_id (order-insensitive)
select ok(
    (select (
        get_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'event_id'::uuid
        )::jsonb->'sessions'->'2025-01-01'
    ) @>
        '[
            {
                "name": "Kubernetes Best Practices",
                "description": "Deep dive into Kubernetes best practices",
                "starts_at": 1735758000,
                "ends_at": 1735760700,
                "kind": "virtual",
                "meeting_hosts": ["session-host@example.com"],
                "meeting_join_url": "https://youtube.com/live/session2",
                "speakers": [
                    {"name": "Host One", "user_id": "00000000-0000-0000-0000-000000000020", "username": "host1", "featured": false},
                    {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2", "featured": true}
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
                    {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1", "featured": true}
                ]
            }
        ]'::jsonb
    ),
    'sessions contain expected rows (ignoring session_id)'
);

-- add_event sets meeting flags (requested/in_sync/password) consistently for events and sessions
with request_event as (
    select add_event(
        :'groupID'::uuid,
        '{
            "name": "Meeting Requested Event",
            "slug": "meeting-requested-event",
            "description": "Event requesting meeting support",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "starts_at": "2025-03-01T10:00:00",
            "ends_at": "2025-03-01T11:30:00",
            "meeting_hosts": ["event-alt-host@example.com"],
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "meeting_requires_password": true,
            "sessions": [
                {
                    "name": "Requested Session",
                    "description": "Session needing meeting",
                    "starts_at": "2025-03-01T10:00:00",
                    "ends_at": "2025-03-01T11:00:00",
                    "kind": "virtual",
                    "meeting_hosts": ["session-alt-host@example.com"],
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true,
                    "meeting_requires_password": true
                }
            ]
        }'::jsonb
    ) as event_id
)
select event_id as event_request_id from request_event \gset
select is(
    (
        select jsonb_build_object(
            'event', jsonb_build_object(
                'meeting_hosts', meeting_hosts,
                'meeting_requested', meeting_requested,
                'meeting_in_sync', meeting_in_sync,
                'meeting_requires_password', meeting_requires_password
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_hosts', meeting_hosts,
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync,
                    'meeting_requires_password', meeting_requires_password
                )
                from session
                where event_id = :'event_request_id'::uuid
            )
        )
        from event
        where event_id = :'event_request_id'::uuid
    ),
    '{
        "event": {
            "meeting_hosts": ["event-alt-host@example.com"],
            "meeting_requested": true,
            "meeting_in_sync": false,
            "meeting_requires_password": true
        },
        "session": {
            "meeting_hosts": ["session-alt-host@example.com"],
            "meeting_requested": true,
            "meeting_in_sync": false,
            "meeting_requires_password": true
        }
    }'::jsonb,
    'add_event sets meeting flags and hosts for event and session when requested'
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

-- add_event throws error for invalid speaker user_id
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Test Event", "slug": "test-event-speaker", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "speakers": [{"user_id": "99999999-9999-9999-9999-999999999999", "featured": false}]}'::jsonb
    )$$,
    'P0001',
    'speaker user 99999999-9999-9999-9999-999999999999 not found in community',
    'add_event should throw error when speaker user_id does not exist in community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
