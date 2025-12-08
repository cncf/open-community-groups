-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(20);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'
\set user3ID '00000000-0000-0000-0000-000000000022'
\set event1ID '00000000-0000-0000-0000-000000000003'
\set event4ID '00000000-0000-0000-0000-000000000004'
\set event5ID '00000000-0000-0000-0000-000000000005'
\set event6ID '00000000-0000-0000-0000-000000000006'
\set event7ID '00000000-0000-0000-0000-000000000007'
\set invalidUserID '99999999-9999-9999-9999-999999999999'
\set meeting1ID '00000000-0000-0000-0000-000000000301'
\set session1ID '00000000-0000-0000-0000-000000000101'
\set session2ID '00000000-0000-0000-0000-000000000102'
\set sponsorNewID '00000000-0000-0000-0000-000000000062'
\set sponsorOrigID '00000000-0000-0000-0000-000000000061'

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
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Users
insert into "user" (user_id, community_id, email, username, auth_hash, name) values
    (:'user1ID', :'community1ID', 'host1@example.com', 'host1', 'hash1', 'Host One'),
    (:'user2ID', :'community1ID', 'host2@example.com', 'host2', 'hash2', 'Host Two'),
    (:'user3ID', :'community1ID', 'speaker1@example.com', 'speaker1', 'hash3', 'Speaker One');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values
    (:'category1ID', 'Conference', 'conference', :'community1ID'),
    (:'category2ID', 'Workshop', 'workshop', :'community1ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'community1ID');

-- Group
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

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null),
    (:'sponsorNewID',  :'group1ID', 'NewSponsor Inc',   'https://example.com/newsponsor.png', 'https://newsponsor.com');

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'event1ID',
    :'group1ID',
    'Original Event',
    'original-event',
    'Original description',
    'America/New_York',
    :'category1ID',
    'in-person'
);

-- Add initial host and sponsor to the event
insert into event_host (event_id, user_id) values (:'event1ID', :'user1ID');
insert into event_speaker (event_id, user_id, featured) values (:'event1ID', :'user1ID', true);
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'event1ID', :'sponsorOrigID', 'Bronze');

-- Event with meeting_in_sync=false for testing preservation
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync,
    starts_at,
    ends_at
) values (
    :'event5ID',
    :'group1ID',
    'Event With Pending Sync',
    'event-pending-sync',
    'This event has a pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    100,
    'zoom',
    true,
    false,
    '2025-03-01 10:00:00-05',
    '2025-03-01 12:00:00-05'
);

-- Event with session having meeting_in_sync=false
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at
) values (
    :'event6ID',
    :'group1ID',
    'Event With Session Pending Sync',
    'event-session-pending-sync',
    'This event has a session with pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2025-04-01 09:00:00-04',
    '2025-04-01 17:00:00-04'
);

insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'session1ID',
    :'event6ID',
    'Session With Pending Sync',
    'Session description',
    '2025-04-01 10:00:00-04',
    '2025-04-01 11:00:00-04',
    'virtual',
    'zoom',
    true,
    false
);

-- Event with session that has a meeting (for orphan test)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published
) values (
    :'event7ID',
    :'group1ID',
    'Event For Session Removal Test',
    'event-session-removal-test',
    'This event has a session with a meeting',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2025-05-01 09:00:00-04',
    '2025-05-01 17:00:00-04',
    true
);

insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested,
    meeting_in_sync
) values (
    :'session2ID',
    :'event7ID',
    'Session To Be Removed',
    'Session description',
    '2025-05-01 10:00:00-04',
    '2025-05-01 11:00:00-04',
    'virtual',
    'zoom',
    true,
    true
);

insert into meeting (join_url, meeting_id, meeting_provider_id, provider_meeting_id, session_id)
values ('https://zoom.us/j/123123123', :'meeting1ID', 'zoom', '123123123', :'session2ID');

-- Canceled Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,

    canceled
) values (
    :'event4ID',
    :'group1ID',
    'Canceled Event',
    'canceled-event',
    'This event was canceled',
    'America/New_York',
    :'category1ID',
    'in-person',

    true
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- update_event returns expected payload when optional collections are omitted
select update_event(
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '{
        "name": "Updated Event Name",
        "slug": "updated-event-slug",
        "description": "Updated description",
        "timezone": "America/Los_Angeles",
        "category_id": "00000000-0000-0000-0000-000000000012",
        "kind_id": "virtual",
        "capacity": 100,
        "starts_at": "2025-02-01T14:00:00",
        "ends_at": "2025-02-01T16:00:00",
        "meeting_provider_id": "zoom",
        "meeting_requested": true
    }'::jsonb
);
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers'
    )),
    '{
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "hosts": [],
        "kind": "virtual",
        "name": "Updated Event Name",
        "published": false,
        "slug": "updated-event-slug",
        "speakers": [],
        "sponsors": [],
        "timezone": "America/Los_Angeles",

        "capacity": 100,
        "remaining_capacity": 100,
        "ends_at": 1738454400,
        "meeting_in_sync": false,
        "meeting_provider": "zoom",
        "meeting_requested": true,
        "sessions": {},
        "starts_at": 1738447200
    }'::jsonb,
    'update_event should update basic fields and clear hosts/sponsors/sessions when not provided'
);

-- update_event sets meeting flags when meeting support is requested (no sessions)
select is(
    (
        select jsonb_build_object(
            'meeting_requested', meeting_requested,
            'meeting_in_sync', meeting_in_sync
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "meeting_requested": true,
        "meeting_in_sync": false
    }'::jsonb,
    'meeting flags are initialized for requested event without sessions'
);

-- update_event updates event, nested relations, and meeting flags with full payload
select update_event(
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '{
        "name": "Fully Updated Event",
        "slug": "fully-updated-event",
        "description": "Fully updated description",
        "timezone": "Asia/Tokyo",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "hybrid",
        "meeting_requested": false,
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "description_short": "Updated short description",
        "starts_at": "2025-02-01T14:00:00",
        "ends_at": "2025-02-01T16:00:00",
        "logo_url": "https://example.com/new-logo.png",
        "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_required": false,
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_name": "New Venue",
        "venue_zip_code": "100-0001",
        "hosts": ["00000000-0000-0000-0000-000000000021", "00000000-0000-0000-0000-000000000022"],
        "speakers": [
            {"user_id": "00000000-0000-0000-0000-000000000021", "featured": true},
            {"user_id": "00000000-0000-0000-0000-000000000022", "featured": false}
        ],
        "sponsors": [{"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Platinum"}],
        "sessions": [
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": "2025-02-01T14:30:00",
                "ends_at": "2025-02-01T15:30:00",
                "kind": "virtual",
                "meeting_hosts": ["session-althost@example.com"],
                "meeting_provider_id": "zoom",
                "meeting_requested": true,
                "speakers": [{"user_id": "00000000-0000-0000-0000-000000000021", "featured": true}]
            }
        ]
    }'::jsonb
);

-- Check event fields except sessions
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions'
    )),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
        "hosts": [
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2"},
            {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1"}
        ],
        "speakers": [
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2", "featured": true},
            {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1", "featured": false}
        ],
        "kind": "hybrid",
        "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
        "meeting_in_sync": false,
        "meeting_requested": false,
        "name": "Fully Updated Event",
        "published": false,
        "slug": "fully-updated-event",
        "timezone": "Asia/Tokyo",
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "remaining_capacity": 200,
        "description_short": "Updated short description",
        "starts_at": 1738386000,
        "ends_at": 1738393200,
        "logo_url": "https://example.com/new-logo.png",
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_required": false,
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_name": "New Venue",
        "venue_zip_code": "100-0001",
        "sponsors": [
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Platinum", "logo_url": "https://example.com/newsponsor.png", "name": "NewSponsor Inc", "website_url": "https://newsponsor.com"}
        ]
    }'::jsonb,
    'update_event should update all fields (excluding sessions)'
);

-- Sessions assertions: contents ignoring session_id (order-insensitive)
select ok(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb->'sessions'->'2025-02-01'
    ) @>
        '[
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": 1738387800,
                "ends_at": 1738391400,
                "kind": "virtual",
                "meeting_hosts": ["session-althost@example.com"],
                "meeting_provider": "zoom",
                "meeting_requested": true,
                "speakers": [
                    {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2", "featured": true}
                ]
            }
        ]'::jsonb
    ),
    'sessions contain expected rows (ignoring session_id)'
);

-- Check meeting flags for event and session
select is(
    (
        select jsonb_build_object(
            'event', jsonb_build_object(
                'meeting_requested', meeting_requested,
                'meeting_in_sync', meeting_in_sync
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync
                )
                from session
                where event_id = :'event1ID'::uuid
            )
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "event": {
            "meeting_requested": false,
            "meeting_in_sync": false
        },
        "session": {
            "meeting_requested": true,
            "meeting_in_sync": false
        }
    }'::jsonb,
    'update_event sets meeting_in_sync=false when meeting disabled to trigger deletion'
);

-- update_event throws error for wrong group_id
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Won''t Work", "slug": "wont-work", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'update_event should throw error when group_id does not match'
);

-- Test: Event meeting_in_sync=false is preserved when updating unrelated fields
select update_event(
    :'group1ID'::uuid,
    :'event5ID'::uuid,
    '{
        "name": "Event With Pending Sync",
        "slug": "event-pending-sync",
        "description": "Updated description - unrelated to meeting",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "capacity": 100,
        "meeting_provider_id": "zoom",
        "meeting_requested": true,
        "starts_at": "2025-03-01T10:00:00",
        "ends_at": "2025-03-01T12:00:00"
    }'::jsonb
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'update_event preserves meeting_in_sync=false when updating unrelated fields'
);

-- Test: Event meeting_in_sync stays false when meeting_requested changes to false
select update_event(
    :'group1ID'::uuid,
    :'event5ID'::uuid,
    '{
        "name": "Event With Pending Sync",
        "slug": "event-pending-sync",
        "description": "Updated description",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "meeting_requested": false,
        "starts_at": "2025-03-01T10:00:00",
        "ends_at": "2025-03-01T12:00:00"
    }'::jsonb
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'update_event keeps meeting_in_sync=false when meeting_requested changes to false'
);

-- Test: Session meeting_in_sync=false is preserved when updating unrelated fields
select update_event(
    :'group1ID'::uuid,
    :'event6ID'::uuid,
    '{
        "name": "Event With Session Pending Sync",
        "slug": "event-session-pending-sync",
        "description": "Updated event description - unrelated to session meeting",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "starts_at": "2025-04-01T09:00:00",
        "ends_at": "2025-04-01T17:00:00",
        "sessions": [
            {
                "session_id": "00000000-0000-0000-0000-000000000101",
                "name": "Session With Pending Sync",
                "description": "Updated session description - unrelated to meeting",
                "starts_at": "2025-04-01T10:00:00",
                "ends_at": "2025-04-01T11:00:00",
                "kind": "virtual",
                "meeting_provider_id": "zoom",
                "meeting_requested": true
            }
        ]
    }'::jsonb
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'update_event preserves session meeting_in_sync=false when updating unrelated fields'
);

-- Test: Session meeting_in_sync stays false when meeting_requested changes to false
select update_event(
    :'group1ID'::uuid,
    :'event6ID'::uuid,
    '{
        "name": "Event With Session Pending Sync",
        "slug": "event-session-pending-sync",
        "description": "Updated event description",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "starts_at": "2025-04-01T09:00:00",
        "ends_at": "2025-04-01T17:00:00",
        "sessions": [
            {
                "session_id": "00000000-0000-0000-0000-000000000101",
                "name": "Session With Pending Sync",
                "description": "Updated session description",
                "starts_at": "2025-04-01T10:00:00",
                "ends_at": "2025-04-01T11:00:00",
                "kind": "virtual",
                "meeting_requested": false
            }
        ]
    }'::jsonb
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'update_event keeps session meeting_in_sync=false when meeting_requested changes to false'
);

select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Try to Update Canceled", "slug": "try-update-canceled", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'update_event should throw error when event is canceled'
);

-- update_event throws error for invalid host user_id
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Event with Invalid Host", "slug": "invalid-host-event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "hosts": ["99999999-9999-9999-9999-999999999999"]}'::jsonb
    )$$,
    'P0001',
    'host user 99999999-9999-9999-9999-999999999999 not found in community',
    'update_event should throw error when host user_id does not exist in community'
);

-- update_event throws error for invalid speaker user_id
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Event with Invalid Speaker", "slug": "invalid-speaker-event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "speakers": [{"user_id": "99999999-9999-9999-9999-999999999999", "featured": false}]}'::jsonb
    )$$,
    'P0001',
    'speaker user 99999999-9999-9999-9999-999999999999 not found in community',
    'update_event should throw error when speaker user_id does not exist in community'
);

-- Test: Session removed via update_event creates orphan meeting
-- First verify session and meeting exist
select ok(
    (select count(*) = 1 from session where session_id = :'session2ID'),
    'session exists before update'
);
-- Update event without the session (removes it via cascade)
select update_event(
    :'group1ID'::uuid,
    :'event7ID'::uuid,
    '{
        "name": "Event For Session Removal Test",
        "slug": "event-session-removal-test",
        "description": "This event has a session with a meeting",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "starts_at": "2025-05-01T09:00:00",
        "ends_at": "2025-05-01T17:00:00",
        "sessions": []
    }'::jsonb
);
-- Verify session is deleted and meeting is now orphan
select is(
    (select count(*) from session where session_id = :'session2ID'),
    0::bigint,
    'session is deleted after update_event with empty sessions'
);
select is(
    (select jsonb_build_object('meeting_id', meeting_id, 'session_id', session_id) from meeting where meeting_id = :'meeting1ID'),
    jsonb_build_object('meeting_id', :'meeting1ID'::uuid, 'session_id', null),
    'meeting becomes orphan (session_id set to null) after session deletion'
);

-- update_event throws error when capacity exceeds max_participants with meeting_requested
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "slug": "event-pending-sync", "description": "Test", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 200, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2025-03-01T10:00:00", "ends_at": "2025-03-01T12:00:00"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'P0001',
    'event capacity (200) exceeds maximum participants allowed (100)',
    'update_event should throw error when capacity exceeds cfg_max_participants with meeting_requested=true'
);

-- update_event succeeds when capacity is within max_participants
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "slug": "event-pending-sync", "description": "Test updated", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 50, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2025-03-01T10:00:00", "ends_at": "2025-03-01T12:00:00"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'update_event should succeed when capacity is within cfg_max_participants'
);

-- update_event succeeds when meeting_requested is false (no capacity check against max_participants)
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "slug": "event-pending-sync", "description": "Test no meeting", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "capacity": 500}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'update_event should succeed with high capacity when meeting_requested is false'
);

-- update_event succeeds when cfg_max_participants is null (no limit configured)
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "slug": "event-pending-sync", "description": "Test no limit", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 1000, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2025-03-01T10:00:00", "ends_at": "2025-03-01T12:00:00"}'::jsonb,
        null
    )$$,
    'update_event should succeed when cfg_max_participants is null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
