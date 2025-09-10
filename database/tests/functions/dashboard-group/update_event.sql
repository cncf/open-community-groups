-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set event1ID '00000000-0000-0000-0000-000000000003'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set user1ID '00000000-0000-0000-0000-000000000020'
\set user2ID '00000000-0000-0000-0000-000000000021'
\set user3ID '00000000-0000-0000-0000-000000000022'
\set invalidUserID '99999999-9999-9999-9999-999999999999'
\set sponsorOrigID '00000000-0000-0000-0000-000000000061'
\set sponsorNewID '00000000-0000-0000-0000-000000000062'

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
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, level, website_url)
values
    (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', 'Bronze', null),
    (:'sponsorNewID',  :'group1ID', 'NewSponsor Inc',   'https://example.com/newsponsor.png', 'Platinum', 'https://newsponsor.com');

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
insert into event_sponsor (event_id, group_sponsor_id)
values (:'event1ID', :'sponsorOrigID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- update_event function updates individual fields (now verifies empty hosts/sessions)
select update_event(
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '{
        "name": "Updated Event Name",
        "slug": "updated-event-slug",
        "description": "Updated description",
        "timezone": "America/Los_Angeles",
        "category_id": "00000000-0000-0000-0000-000000000012",
        "kind_id": "virtual"
    }'::jsonb
);

select is(
    (select (get_event_full('00000000-0000-0000-0000-000000000003'::uuid)::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group')),
    '{
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "hosts": [],
        "kind": "virtual",
        "name": "Updated Event Name",
        "published": false,
        "sponsors": [],
        "sessions": [],
        "slug": "updated-event-slug",
        "timezone": "America/Los_Angeles"
    }'::jsonb,
    'update_event should update basic fields and clear hosts/sponsors/sessions when not provided'
);

-- update_event function updates all fields including hosts, sponsors, and sessions
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
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "description_short": "Updated short description",
        "starts_at": "2025-02-01T14:00:00",
        "ends_at": "2025-02-01T16:00:00",
        "logo_url": "https://example.com/new-logo.png",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "recording_url": "https://youtube.com/new-recording",
        "registration_required": false,
        "streaming_url": "https://youtube.com/new-live",
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_name": "New Venue",
        "venue_zip_code": "100-0001",
        "hosts": ["00000000-0000-0000-0000-000000000021", "00000000-0000-0000-0000-000000000022"],
        "sponsors": ["00000000-0000-0000-0000-000000000062"],
        "sessions": [
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": "2025-02-01T14:30:00",
                "ends_at": "2025-02-01T15:30:00",
                "kind": "virtual",
                "streaming_url": "https://youtube.com/live/updated",
                "speakers": ["00000000-0000-0000-0000-000000000021"]
            }
        ]
    }'::jsonb
);

select is(
    (select (get_event_full('00000000-0000-0000-0000-000000000003'::uuid)::jsonb - 'created_at' - 'event_id' - 'organizers' - 'group' - 'sessions'))
        -- Add back sessions without session_ids (which are random)
        || jsonb_build_object('sessions', 
            (select jsonb_agg(session - 'session_id')
             from jsonb_array_elements((
                select (get_event_full('00000000-0000-0000-0000-000000000003'::uuid)::jsonb->'sessions')
             )) as session)
        ),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
        "hosts": [
            {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2"},
            {"name": "Speaker One", "user_id": "00000000-0000-0000-0000-000000000022", "username": "speaker1"}
        ],
        "kind": "hybrid",
        "name": "Fully Updated Event",
        "published": false,
        "slug": "fully-updated-event",
        "timezone": "Asia/Tokyo",
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "description_short": "Updated short description",
        "starts_at": 1738386000,
        "ends_at": 1738393200,
        "logo_url": "https://example.com/new-logo.png",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "recording_url": "https://youtube.com/new-recording",
        "registration_required": false,
        "streaming_url": "https://youtube.com/new-live",
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_name": "New Venue",
        "venue_zip_code": "100-0001",
        "sponsors": [
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "level": "Platinum", "logo_url": "https://example.com/newsponsor.png", "name": "NewSponsor Inc", "website_url": "https://newsponsor.com"}
        ],
        "sessions": [
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": 1738387800,
                "ends_at": 1738391400,
                "kind": "virtual",
                "streaming_url": "https://youtube.com/live/updated",
                "speakers": [
                    {"name": "Host Two", "user_id": "00000000-0000-0000-0000-000000000021", "username": "host2"}
                ]
            }
        ]
    }'::jsonb,
    'update_event should update all fields including hosts, sponsors, and sessions'
);

-- update_event throws error for wrong group_id
select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid,
        '{"name": "Won''t Work", "slug": "wont-work", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'P0001',
    'event not found',
    'update_event should throw error when group_id does not match'
);

-- update_event throws error for canceled event
-- First, create a canceled event for testing
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
    '00000000-0000-0000-0000-000000000004',
    :'group1ID',
    'Canceled Event',
    'canceled-event',
    'This event was canceled',
    'America/New_York',
    :'category1ID',
    'in-person',
    true
);

select throws_ok(
    $$select update_event(
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Try to Update Canceled", "slug": "try-update-canceled", "description": "This should fail", "timezone": "UTC", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
    )$$,
    'P0001',
    'event not found',
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
