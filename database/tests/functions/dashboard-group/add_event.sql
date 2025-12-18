-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(24);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set invalidUserID '99999999-9999-9999-9999-999999999999'
\set sponsor1ID '00000000-0000-0000-0000-000000000061'
\set sponsor2ID '00000000-0000-0000-0000-000000000062'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'
\set user3ID '00000000-0000-0000-0000-000000000022'

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
    'abc1234',
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

-- Should create event with minimal required fields and return expected structure
select ok(
    (select (
        get_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            add_event(
                :'groupID'::uuid,
                '{"name": "Kubernetes Fundamentals Workshop", "description": "Learn the basics of Kubernetes deployment and management", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
            )
        )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'slug'
    )) = '{
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
        "timezone": "America/New_York"
    }'::jsonb,
    'Should create event with minimal required fields and return expected structure'
);

-- Should create event with all fields including hosts, sponsors, and sessions
with new_event as (
    select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{
            "name": "CloudNativeCon Seattle 2025",
            "description": "Premier conference for cloud native technologies and community collaboration",
            "timezone": "America/Los_Angeles",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "hybrid",
            "banner_url": "https://example.com/banner.jpg",
            "capacity": 100,
            "description_short": "Short description",
            "starts_at": "2030-01-01T10:00:00",
            "ends_at": "2030-01-01T12:00:00",
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
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Tech Center",
            "venue_state": "CA",
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
                    "starts_at": "2030-01-01T10:00:00",
                    "ends_at": "2030-01-01T10:45:00",
                    "kind": "in-person",
                    "location": "Main Hall",
                    "speakers": [{"user_id": "00000000-0000-0000-0000-000000000022", "featured": true}]
                },
                {
                    "name": "Kubernetes Best Practices",
                    "description": "Deep dive into Kubernetes best practices",
                    "starts_at": "2030-01-01T11:00:00",
                    "ends_at": "2030-01-01T11:45:00",
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
select ok(
    (select get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'event_id'::uuid
    )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions' - 'slug') = '{
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
        "timezone": "America/Los_Angeles",
        "banner_url": "https://example.com/banner.jpg",
        "capacity": 100,
        "remaining_capacity": 100,
        "description_short": "Short description",
        "starts_at": 1893520800,
        "ends_at": 1893528000,
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
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Tech Center",
        "venue_state": "CA",
        "venue_zip_code": "94105",
        "sponsors": [
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Silver", "logo_url": "https://example.com/cloudinc.png", "name": "CloudInc"},
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "level": "Gold", "logo_url": "https://example.com/techcorp.png", "name": "TechCorp", "website_url": "https://techcorp.com"}
        ]
    }'::jsonb,
    'Should create event with all fields (excluding sessions)'
);


-- Sessions should contain expected rows (ignoring session_id)
select ok(
    (select (
        get_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'event_id'::uuid
        )::jsonb->'sessions'->'2030-01-01'
    ) @>
        '[
            {
                "name": "Kubernetes Best Practices",
                "description": "Deep dive into Kubernetes best practices",
                "starts_at": 1893524400,
                "ends_at": 1893527100,
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
                "starts_at": 1893520800,
                "ends_at": 1893523500,
                "kind": "in-person",
                "location": "Main Hall",
                "speakers": [
                    {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1", "featured": true}
                ]
            }
        ]'::jsonb
    ),
    'Sessions contain expected rows (ignoring session_id)'
);

-- Should set meeting flags consistently for events and sessions when requested
with request_event as (
    select add_event(
        :'groupID'::uuid,
        '{
            "name": "Meeting Requested Event",
            "description": "Event requesting meeting support",
            "timezone": "UTC",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "kind_id": "virtual",
            "capacity": 100,
            "starts_at": "2030-03-01T10:00:00",
            "ends_at": "2030-03-01T11:30:00",
            "meeting_hosts": ["event-alt-host@example.com"],
            "meeting_provider_id": "zoom",
            "meeting_requested": true,
            "sessions": [
                {
                    "name": "Requested Session",
                    "description": "Session needing meeting",
                    "starts_at": "2030-03-01T10:00:00",
                    "ends_at": "2030-03-01T11:00:00",
                    "kind": "virtual",
                    "meeting_hosts": ["session-alt-host@example.com"],
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true
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
                'meeting_in_sync', meeting_in_sync
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_hosts', meeting_hosts,
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync
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
            "meeting_in_sync": false
        },
        "session": {
            "meeting_hosts": ["session-alt-host@example.com"],
            "meeting_requested": true,
            "meeting_in_sync": false
        }
    }'::jsonb,
    'Should set meeting flags and hosts for event and session when requested'
);

-- Should throw error for invalid host user_id
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Test Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "hosts": ["99999999-9999-9999-9999-999999999999"]}'::jsonb
    )$$,
    'user not found in community',
    'Should throw error when host user_id does not exist in community'
);

-- Should throw error for invalid speaker user_id
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Test Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "speakers": [{"user_id": "99999999-9999-9999-9999-999999999999", "featured": false}]}'::jsonb
    )$$,
    'user not found in community',
    'Should throw error when speaker user_id does not exist in community'
);

-- Should throw error when capacity exceeds max_participants with meeting_requested
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Capacity Exceed Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 200, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2030-03-01T10:00:00", "ends_at": "2030-03-01T11:00:00"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'event capacity (200) exceeds maximum participants allowed (100)',
    'Should throw error when capacity exceeds cfg_max_participants with meeting_requested=true'
);

-- Should succeed when capacity is within max_participants
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Valid Capacity Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 50, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2030-03-01T10:00:00", "ends_at": "2030-03-01T11:00:00"}'::jsonb,
        '{"zoom": 100}'::jsonb
    ) is not null),
    'Should succeed when capacity is within cfg_max_participants'
);

-- Should succeed with high capacity when meeting_requested is false
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "No Meeting Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "capacity": 500}'::jsonb,
        '{"zoom": 100}'::jsonb
    ) is not null),
    'Should succeed with high capacity when meeting_requested is false'
);

-- Should succeed when cfg_max_participants is null
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "No Limit Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 1000, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2030-03-01T10:00:00", "ends_at": "2030-03-01T11:00:00"}'::jsonb,
        null
    ) is not null),
    'Should succeed when cfg_max_participants is null'
);

-- Should throw error when event starts_at is in the past
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Past Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2020-01-01T10:00:00"}'::jsonb
    )$$,
    'event starts_at cannot be in the past',
    'Should throw error when event starts_at is in the past'
);

-- Should throw error when event ends_at is in the past
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Past End Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "ends_at": "2020-01-01T12:00:00"}'::jsonb
    )$$,
    'event ends_at cannot be in the past',
    'Should throw error when event ends_at is in the past'
);

-- Should throw error when session starts_at is in the past
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session Past Start", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Past Session", "starts_at": "2020-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at cannot be in the past',
    'Should throw error when session starts_at is in the past'
);

-- Should throw error when session ends_at is in the past
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session Past End", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Past End Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2020-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at cannot be in the past',
    'Should throw error when session ends_at is in the past'
);

-- Should throw error when event ends_at is before starts_at
select throws_like(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Invalid Range Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00"}'::jsonb
    )$$,
    '%event_ends_at_after_starts_at_check%',
    'Should throw error when event ends_at is before starts_at'
);

-- Should throw error when session ends_at is before starts_at
select throws_like(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Invalid Session Range", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Invalid Session", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    '%session_ends_at_after_starts_at_check%',
    'Should throw error when session ends_at is before starts_at'
);

-- Should throw error when event ends_at is set without starts_at
select throws_like(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "No Start Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "ends_at": "2030-01-01T12:00:00"}'::jsonb
    )$$,
    '%event_ends_at_after_starts_at_check%',
    'Should throw error when event ends_at is set without starts_at'
);

-- Should succeed with event ends_at null when starts_at is null
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "No Dates Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    ) is not null),
    'Should succeed with event ends_at null when starts_at is null'
);

-- Should succeed with session ends_at null when starts_at is set
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session No End", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "No End Session", "starts_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    ) is not null),
    'Should succeed with session ends_at null when starts_at is set'
);

-- Should succeed with valid future dates for event and sessions
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Future Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Future Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    ) is not null),
    'Should succeed with valid future dates for event and sessions'
);

-- Should throw error when session starts_at is before event starts_at
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session Before Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Early Session", "starts_at": "2030-01-01T09:00:00", "ends_at": "2030-01-01T10:30:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is before event starts_at'
);

-- Should throw error when session starts_at is after event ends_at
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session After Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Late Session", "starts_at": "2030-01-01T13:00:00", "ends_at": "2030-01-01T14:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is after event ends_at'
);

-- Should throw error when session ends_at is after event ends_at
select throws_ok(
    $$select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session Exceeds Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Long Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T13:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at must be within event bounds',
    'Should throw error when session ends_at is after event ends_at'
);

-- Should succeed when session is within event bounds
select ok(
    (select add_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '{"name": "Session Within Bounds", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T14:00:00", "sessions": [{"name": "Valid Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T12:00:00", "kind": "in-person"}]}'::jsonb
    ) is not null),
    'Should succeed when session is within event bounds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
