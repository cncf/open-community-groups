-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(42);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set community1ID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000003'
\set event4ID '00000000-0000-0000-0000-000000000004'
\set event5ID '00000000-0000-0000-0000-000000000005'
\set event6ID '00000000-0000-0000-0000-000000000006'
\set event7ID '00000000-0000-0000-0000-000000000007'
\set event8ID '00000000-0000-0000-0000-000000000008'
\set event9ID '00000000-0000-0000-0000-000000000009'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set invalidUserID '99999999-9999-9999-9999-999999999999'
\set meeting1ID '00000000-0000-0000-0000-000000000301'
\set session1ID '00000000-0000-0000-0000-000000000101'
\set session2ID '00000000-0000-0000-0000-000000000102'
\set sponsorNewID '00000000-0000-0000-0000-000000000062'
\set sponsorOrigID '00000000-0000-0000-0000-000000000061'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'
\set user3ID '00000000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_url)
values (:'community1ID', 'test-community', 'Test Community', 'A test community for testing purposes', 'https://example.com/logo.png', 'https://example.com/banner.png');

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user2ID', 'hash2', 'host2@example.com', 'host2', 'Host Two'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One');

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
    'abc1234',
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
    'def5678',
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
    'ghi9abc',
    'This event has a pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    100,
    'zoom',
    true,
    false,
    '2030-03-01 10:00:00-05',
    '2030-03-01 12:00:00-05'
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
    'jkl2def',
    'This event has a session with pending meeting sync',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2030-04-01 09:00:00-04',
    '2030-04-01 17:00:00-04'
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
    '2030-04-01 10:00:00-04',
    '2030-04-01 11:00:00-04',
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
    'mno3ghi',
    'This event has a session with a meeting',
    'America/New_York',
    :'category1ID',
    'virtual',
    '2030-05-01 09:00:00-04',
    '2030-05-01 17:00:00-04',
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
    '2030-05-01 10:00:00-04',
    '2030-05-01 11:00:00-04',
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
    'pqr4jkl',
    'This event was canceled',
    'America/New_York',
    :'category1ID',
    'in-person',

    true
);

-- Past Event (for testing limited updates)
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

    description_short,
    photos_urls,
    tags,
    venue_name
) values (
    :'event8ID',
    :'group1ID',
    'Past Event',
    'stu5mno',
    'This event already happened',
    'America/New_York',
    :'category1ID',
    'in-person',
    '2020-01-01 10:00:00-05',
    '2020-01-01 12:00:00-05',

    'Original short description',
    array['https://example.com/original-photo.jpg'],
    array['original', 'tags'],
    'Original Venue'
);

-- Live Event (started in the past, ends in the future)
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
    :'event9ID',
    :'group1ID',
    'Live Event',
    'vwx6pqr',
    'This event is currently live',
    'UTC',
    :'category1ID',
    'in-person',
    current_timestamp - interval '1 hour',
    current_timestamp + interval '2 hours'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update basic fields and clear hosts/sponsors/sessions when not provided
select update_event(
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '{
        "name": "Updated Event Name",
        "description": "Updated description",
        "timezone": "America/Los_Angeles",
        "category_id": "00000000-0000-0000-0000-000000000012",
        "kind_id": "virtual",
        "capacity": 100,
        "starts_at": "2030-02-01T14:00:00",
        "ends_at": "2030-02-01T16:00:00",
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
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers'
    )),
    '{
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "hosts": [],
        "kind": "virtual",
        "name": "Updated Event Name",
        "published": false,
        "slug": "def5678",
        "speakers": [],
        "sponsors": [],
        "timezone": "America/Los_Angeles",

        "capacity": 100,
        "remaining_capacity": 100,
        "ends_at": 1896220800,
        "meeting_in_sync": false,
        "meeting_provider": "zoom",
        "meeting_requested": true,
        "sessions": {},
        "starts_at": 1896213600
    }'::jsonb,
    'Should update basic fields and clear hosts/sponsors/sessions when not provided'
);

-- Should initialize meeting flags for requested event without sessions
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
    'Meeting flags are initialized for requested event without sessions'
);

-- Should update all fields (excluding sessions) with full payload
select update_event(
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '{
        "name": "Fully Updated Event",
        "description": "Fully updated description",
        "timezone": "Asia/Tokyo",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "hybrid",
        "meeting_requested": false,
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "description_short": "Updated short description",
        "starts_at": "2030-02-01T14:00:00",
        "ends_at": "2030-02-01T16:00:00",
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
        "venue_country_code": "JP",
        "venue_country_name": "Japan",
        "venue_name": "New Venue",
        "venue_state": "TK",
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
                "starts_at": "2030-02-01T14:30:00",
                "ends_at": "2030-02-01T15:30:00",
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
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions'
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
        "slug": "def5678",
        "timezone": "Asia/Tokyo",
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "remaining_capacity": 200,
        "description_short": "Updated short description",
        "starts_at": 1896152400,
        "ends_at": 1896159600,
        "logo_url": "https://example.com/new-logo.png",
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_required": false,
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_country_code": "JP",
        "venue_country_name": "Japan",
        "venue_name": "New Venue",
        "venue_state": "TK",
        "venue_zip_code": "100-0001",
        "sponsors": [
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Platinum", "logo_url": "https://example.com/newsponsor.png", "name": "NewSponsor Inc", "website_url": "https://newsponsor.com"}
        ]
    }'::jsonb,
    'Should update all fields (excluding sessions)'
);

-- Should contain expected session rows (ignoring session_id)
select ok(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb->'sessions'->'2030-02-01'
    ) @>
        '[
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": 1896154200,
                "ends_at": 1896157800,
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
    'Sessions contain expected rows (ignoring session_id)'
);

-- Should set meeting_in_sync=false when meeting disabled to trigger deletion
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
    'Should set meeting_in_sync=false when meeting disabled to trigger deletion'
);

-- Should throw error when group_id does not match
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Won''t Work", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should preserve meeting_in_sync=false when updating unrelated fields
select update_event(
    :'group1ID'::uuid,
    :'event5ID'::uuid,
    '{
        "name": "Event With Pending Sync",
        "description": "Updated description - unrelated to meeting",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "capacity": 100,
        "meeting_provider_id": "zoom",
        "meeting_requested": true,
        "starts_at": "2030-03-01T10:00:00",
        "ends_at": "2030-03-01T12:00:00"
    }'::jsonb
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should preserve meeting_in_sync=false when updating unrelated fields'
);

-- Should keep meeting_in_sync=false when meeting_requested changes to false
select update_event(
    :'group1ID'::uuid,
    :'event5ID'::uuid,
    '{
        "name": "Event With Pending Sync",
        "description": "Updated description",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "meeting_requested": false,
        "starts_at": "2030-03-01T10:00:00",
        "ends_at": "2030-03-01T12:00:00"
    }'::jsonb
);
select is(
    (select meeting_in_sync from event where event_id = :'event5ID'::uuid),
    false,
    'Should keep meeting_in_sync=false when meeting_requested changes to false'
);

-- Should preserve session meeting_in_sync=false when updating unrelated fields
select update_event(
    :'group1ID'::uuid,
    :'event6ID'::uuid,
    '{
        "name": "Event With Session Pending Sync",
        "description": "Updated event description - unrelated to session meeting",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "starts_at": "2030-04-01T09:00:00",
        "ends_at": "2030-04-01T17:00:00",
        "sessions": [
            {
                "session_id": "00000000-0000-0000-0000-000000000101",
                "name": "Session With Pending Sync",
                "description": "Updated session description - unrelated to meeting",
                "starts_at": "2030-04-01T10:00:00",
                "ends_at": "2030-04-01T11:00:00",
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
    'Should preserve session meeting_in_sync=false when updating unrelated fields'
);

-- Should keep session meeting_in_sync=false when meeting_requested changes to false
select update_event(
    :'group1ID'::uuid,
    :'event6ID'::uuid,
    '{
        "name": "Event With Session Pending Sync",
        "description": "Updated event description",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "starts_at": "2030-04-01T09:00:00",
        "ends_at": "2030-04-01T17:00:00",
        "sessions": [
            {
                "session_id": "00000000-0000-0000-0000-000000000101",
                "name": "Session With Pending Sync",
                "description": "Updated session description",
                "starts_at": "2030-04-01T10:00:00",
                "ends_at": "2030-04-01T11:00:00",
                "kind": "virtual",
                "meeting_requested": false
            }
        ]
    }'::jsonb
);
select is(
    (select meeting_in_sync from session where session_id = :'session1ID'::uuid),
    false,
    'Should keep session meeting_in_sync=false when meeting_requested changes to false'
);

select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Try to Update Canceled", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when event is canceled'
);

-- Should throw error for invalid host user_id (FK violation)
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Event with Invalid Host", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "hosts": ["99999999-9999-9999-9999-999999999999"]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when host user_id does not exist'
);

-- Should throw error for invalid speaker user_id (FK violation)
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Event with Invalid Speaker", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "speakers": [{"user_id": "99999999-9999-9999-9999-999999999999", "featured": false}]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when speaker user_id does not exist'
);

-- Should verify session exists before update
select ok(
    (select count(*) = 1 from session where session_id = :'session2ID'),
    'Session exists before update'
);
-- Update event without the session (removes it via cascade)
select update_event(
    :'group1ID'::uuid,
    :'event7ID'::uuid,
    '{
        "name": "Event For Session Removal Test",
        "description": "This event has a session with a meeting",
        "timezone": "America/New_York",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "kind_id": "virtual",
        "starts_at": "2030-05-01T09:00:00",
        "ends_at": "2030-05-01T17:00:00",
        "sessions": []
    }'::jsonb
);
-- Should verify session is deleted and meeting is orphan after update
select is(
    (select count(*) from session where session_id = :'session2ID'),
    0::bigint,
    'Session is deleted after update_event with empty sessions'
);
select is(
    (select jsonb_build_object('meeting_id', meeting_id, 'session_id', session_id) from meeting where meeting_id = :'meeting1ID'),
    jsonb_build_object('meeting_id', :'meeting1ID'::uuid, 'session_id', null),
    'Meeting becomes orphan (session_id set to null) after session deletion'
);

-- Should throw error when capacity exceeds max_participants with meeting_requested
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "description": "Test", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 200, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2030-03-01T10:00:00", "ends_at": "2030-03-01T12:00:00"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'event capacity (200) exceeds maximum participants allowed (100)',
    'Should throw error when capacity exceeds cfg_max_participants with meeting_requested=true'
);

-- Should succeed when capacity is within max_participants
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "description": "Test updated", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 50, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2030-03-01T10:00:00", "ends_at": "2030-03-01T12:00:00"}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'Should succeed when capacity is within cfg_max_participants'
);

-- Should succeed with high capacity when meeting_requested is false
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "description": "Test no meeting", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "capacity": 500}'::jsonb,
        '{"zoom": 100}'::jsonb
    )$$,
    'Should succeed with high capacity when meeting_requested is false'
);

-- Should succeed when cfg_max_participants is null
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Event With Pending Sync", "description": "Test no limit", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "virtual", "capacity": 1000, "meeting_requested": true, "meeting_provider_id": "zoom", "starts_at": "2030-03-01T10:00:00", "ends_at": "2030-03-01T12:00:00"}'::jsonb,
        null
    )$$,
    'Should succeed when cfg_max_participants is null'
);

-- Should throw error when event starts_at is in the past
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Past Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2020-01-01T10:00:00"}'::jsonb
    )$$,
    'event starts_at cannot be in the past',
    'Should throw error when event starts_at is in the past'
);

-- Should throw error when event ends_at is in the past
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Past End Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "ends_at": "2020-01-01T12:00:00"}'::jsonb
    )$$,
    'event ends_at cannot be in the past',
    'Should throw error when event ends_at is in the past'
);

-- Should throw error when session starts_at is in the past
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Past Start", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Past Session", "starts_at": "2020-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at cannot be in the past',
    'Should throw error when session starts_at is in the past'
);

-- Should throw error when session ends_at is in the past
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Past End", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Past End Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2020-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at cannot be in the past',
    'Should throw error when session ends_at is in the past'
);

-- Should throw error when event ends_at is before starts_at
select throws_like(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Invalid Range Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00"}'::jsonb
    )$$,
    '%event_check%',
    'Should throw error when event ends_at is before starts_at'
);

-- Should throw error when session ends_at is before starts_at
select throws_like(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Invalid Session Range", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Invalid Session", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    '%session_check%',
    'Should throw error when session ends_at is before starts_at'
);

-- Should throw error when event ends_at is set without starts_at
select throws_like(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "No Start Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "ends_at": "2030-01-01T12:00:00"}'::jsonb
    )$$,
    '%event_check%',
    'Should throw error when event ends_at is set without starts_at'
);

-- Should succeed with event ends_at null when starts_at is null
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "No Dates Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'Should succeed with event ends_at null when starts_at is null'
);

-- Should succeed with session ends_at null when starts_at is set
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session No End", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "No End Session", "starts_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed with session ends_at null when starts_at is set'
);

-- Should succeed with valid future dates for event and sessions
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Future Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Future Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed with valid future dates for event and sessions'
);

-- Should throw error when session starts_at is before event starts_at
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Before Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Early Session", "starts_at": "2030-01-01T09:00:00", "ends_at": "2030-01-01T10:30:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is before event starts_at'
);

-- Should throw error when session starts_at is after event ends_at
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session After Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Late Session", "starts_at": "2030-01-01T13:00:00", "ends_at": "2030-01-01T14:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is after event ends_at'
);

-- Should throw error when session ends_at is after event ends_at
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Exceeds Event", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Long Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T13:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at must be within event bounds',
    'Should throw error when session ends_at is after event ends_at'
);

-- Should succeed when session is within event bounds
select lives_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Session Within Bounds", "description": "Test", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T14:00:00", "sessions": [{"name": "Valid Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T12:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed when session is within event bounds'
);

-- Should update allowed fields and ignore restricted fields on past events
select update_event(
    :'group1ID'::uuid,
    :'event8ID'::uuid,
    '{
        "name": "Attempted Name Change",
        "description": "Updated description for past event",
        "description_short": "Updated short description",
        "timezone": "Asia/Tokyo",
        "category_id": "00000000-0000-0000-0000-000000000012",
        "kind_id": "virtual",
        "capacity": 999,
        "starts_at": "2030-06-01T10:00:00",
        "ends_at": "2030-06-01T12:00:00",
        "meeting_requested": true,
        "meeting_provider_id": "zoom",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "meeting_recording_url": "https://youtube.com/recording",
        "tags": ["updated", "past", "event"],
        "banner_url": "https://example.com/banner.jpg",
        "logo_url": "https://example.com/logo.png",
        "venue_address": "123 Updated St",
        "venue_city": "Updated City",
        "venue_name": "Updated Venue",
        "venue_zip_code": "12345"
    }'::jsonb
);
-- Verify allowed fields were updated
select is(
    (
        select jsonb_build_object(
            'banner_url', banner_url,
            'description', description,
            'description_short', description_short,
            'logo_url', logo_url,
            'meeting_recording_url', meeting_recording_url,
            'photos_urls', photos_urls,
            'tags', tags
        )
        from event
        where event_id = :'event8ID'::uuid
    ),
    '{
        "banner_url": "https://example.com/banner.jpg",
        "description": "Updated description for past event",
        "description_short": "Updated short description",
        "logo_url": "https://example.com/logo.png",
        "meeting_recording_url": "https://youtube.com/recording",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "tags": ["updated", "past", "event"]
    }'::jsonb,
    'Should update allowed fields on past events'
);

-- Verify restricted fields were ignored despite being in payload
select is(
    (
        select jsonb_build_object(
            'capacity', capacity,
            'ends_at', ends_at,
            'event_category_id', event_category_id,
            'event_kind_id', event_kind_id,
            'meeting_provider_id', meeting_provider_id,
            'meeting_requested', meeting_requested,
            'name', name,
            'starts_at', starts_at,
            'timezone', timezone,

            'venue_address', venue_address,
            'venue_city', venue_city,
            'venue_name', venue_name,
            'venue_zip_code', venue_zip_code
        )
        from event
        where event_id = :'event8ID'::uuid
    ),
    jsonb_build_object(
        'capacity', null,
        'ends_at', '2020-01-01 17:00:00+00'::timestamptz,
        'event_category_id', :'category1ID'::uuid,
        'event_kind_id', 'in-person',
        'meeting_provider_id', null,
        'meeting_requested', null,
        'name', 'Past Event',
        'starts_at', '2020-01-01 15:00:00+00'::timestamptz,
        'timezone', 'America/New_York',

        'venue_address', null,
        'venue_city', null,
        'venue_name', 'Original Venue',
        'venue_zip_code', null
    ),
    'Should ignore restricted fields on past events despite being in payload'
);

-- Should ignore hosts/speakers/sponsors on past events despite being in payload
select update_event(
    :'group1ID'::uuid,
    :'event8ID'::uuid,
    '{
        "description": "Another update with hosts",
        "hosts": ["00000000-0000-0000-0000-000000000020", "00000000-0000-0000-0000-000000000021"],
        "speakers": [{"user_id": "00000000-0000-0000-0000-000000000022", "featured": true}],
        "sponsors": [{"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "level": "Gold"}]
    }'::jsonb
);
select is(
    (select count(*) from event_host where event_id = :'event8ID'::uuid),
    0::bigint,
    'Should ignore hosts on past events despite being in payload'
);
select is(
    (select count(*) from event_speaker where event_id = :'event8ID'::uuid),
    0::bigint,
    'Should ignore speakers on past events despite being in payload'
);
select is(
    (select count(*) from event_sponsor where event_id = :'event8ID'::uuid),
    0::bigint,
    'Should ignore sponsors on past events despite being in payload'
);

-- Should succeed updating live event when starts_at is unchanged
select lives_ok(
    format(
        $$select update_event(
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated',
                'description', 'Updated description',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'Should succeed updating live event when starts_at is unchanged'
);

-- Should succeed updating live event when starts_at is moved later (but still in past)
select lives_ok(
    format(
        $$select update_event(
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated Again',
                'description', 'Updated description again',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC' + interval '30 minutes', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'Should succeed updating live event when starts_at is moved later (but still in past)'
);

-- Should throw error when trying to backdate starts_at on live event
select throws_ok(
    format(
        $$select update_event(
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Backdated',
                'description', 'Trying to backdate',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC' - interval '30 minutes', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'event starts_at cannot be earlier than current value',
    'Should throw error when trying to backdate starts_at on live event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
