-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendee1ID '00000000-0000-0000-0000-000000000041'
\set attendee2ID '00000000-0000-0000-0000-000000000042'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000021'

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
values (:'categoryID', 'Technology', :'communityID');

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
    city,
    state,
    country_code,
    country_name,
    location,
    logo_url
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'abc1234',
    :'communityID',
    :'categoryID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    'https://example.com/group-logo.png'
);

-- Attendees for remaining capacity verification
insert into "user" (
    user_id,
    email,
    username,
    email_verified,
    auth_hash,
    community_id,
    created_at
) values (
    :'attendee1ID',
    'attendee1@example.com',
    'attendee1',
    true,
    'attendee-hash',
    :'communityID',
    '2024-01-01 00:00:00+00'
), (
    :'attendee2ID',
    'attendee2@example.com',
    'attendee2',
    true,
    'attendee-hash',
    :'communityID',
    '2024-01-01 00:00:00+00'
);

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    event_kind_id,
    event_category_id,
    group_id,
    published,
    starts_at,
    ends_at,
    timezone,
    meeting_join_url,
    venue_address,
    venue_city,
    venue_name,
    venue_zip_code,
    capacity,
    location,
    logo_url
) values (
    :'eventID',
    'KubeCon Seattle 2024',
    'def5678',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts',
    'Annual Kubernetes conference short summary',
    'in-person',
    :'eventCategoryID',
    :'groupID',
    true,
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
    'America/New_York',
    null,
    '123 Main St',
    'New York',
    'Convention Center',
    '10001',
    5,
    ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326),  -- Seattle coordinates (different from group)
    'https://example.com/event-logo.png'
);

-- Link meeting to event
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventID',
    'https://meeting.example.com/summary',
    'zoom',
    'secret123',
    'summary-meeting-001'
);

-- Event Attendees
insert into event_attendee (event_id, user_id)
values
    (:'eventID', :'attendee1ID'),
    (:'eventID', :'attendee2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct event summary data as JSON
select is(
    get_event_summary(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb,
    '{
        "canceled": false,
        "event_id": "00000000-0000-0000-0000-000000000031",
        "group_category_name": "Technology",
        "group_name": "Seattle Kubernetes Meetup",
        "group_slug": "abc1234",
        "kind": "in-person",
        "name": "KubeCon Seattle 2024",
        "published": true,
        "slug": "def5678",
        "timezone": "America/New_York",
        "description_short": "Annual Kubernetes conference short summary",
        "ends_at": 1718470800,
        "group_city": "New York",
        "group_country_code": "US",
        "group_country_name": "United States",
        "group_latitude": 40.7128,
        "group_longitude": -74.006,
        "group_state": "NY",
        "latitude": 47.6062,
        "logo_url": "https://example.com/event-logo.png",
        "longitude": -122.3321,
        "meeting_join_url": "https://meeting.example.com/summary",
        "meeting_password": "secret123",
        "starts_at": 1718442000,
        "venue_address": "123 Main St",
        "venue_city": "New York",
        "venue_name": "Convention Center",
        "zip_code": "10001",
        "remaining_capacity": 3
    }'::jsonb,
    'Should return correct event summary data as JSON'
);

-- Should return null for non-existent event ID
select ok(
    get_event_summary(
        :'communityID'::uuid,
        :'groupID'::uuid,
        '00000000-0000-0000-0000-000000999999'::uuid
    ) is null,
    'Should return null for non-existent event ID'
);

-- Should return null when group does not match event
select ok(
    get_event_summary(
        :'communityID'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid,
        :'eventID'::uuid
    ) is null,
    'Should return null when group does not match event'
);

-- Should return null when community does not match event
select ok(
    get_event_summary(
        '00000000-0000-0000-0000-000000000002'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    ) is null,
    'Should return null when community does not match event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
