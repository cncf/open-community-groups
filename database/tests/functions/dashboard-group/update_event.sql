-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set community1ID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set event1ID '00000000-0000-0000-0000-000000000003'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (for testing event updates)
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

-- Event categories (for testing category updates)
insert into event_category (event_category_id, name, slug, community_id)
values
    (:'category1ID', 'Conference', 'conference', :'community1ID'),
    (:'category2ID', 'Workshop', 'workshop', :'community1ID');

-- Group category (for group organization)
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'community1ID');

-- Group (for hosting events)
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

-- Event (target for update testing)
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

-- ============================================================================
-- TESTS
-- ============================================================================

-- update_event function updates individual fields
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
    (select (get_event_full('00000000-0000-0000-0000-000000000003'::uuid)::jsonb - 'created_at' - 'event_id' - 'hosts' - 'organizers' - 'sessions' - 'group')),
    '{
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "kind": "virtual",
        "name": "Updated Event Name",
        "published": false,
        "slug": "updated-event-slug",
        "timezone": "America/Los_Angeles"
    }'::jsonb,
    'update_event should update basic fields correctly'
);

-- update_event function updates all optional fields
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
        "venue_zip_code": "100-0001"
    }'::jsonb
);

select is(
    (select (get_event_full('00000000-0000-0000-0000-000000000003'::uuid)::jsonb - 'created_at' - 'event_id' - 'hosts' - 'organizers' - 'sessions' - 'group')),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
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
        "venue_zip_code": "100-0001"
    }'::jsonb,
    'update_event should update all fields correctly'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
