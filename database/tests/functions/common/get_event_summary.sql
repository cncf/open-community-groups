-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000021'
\set attendee1ID '00000000-0000-0000-0000-000000000041'
\set attendee2ID '00000000-0000-0000-0000-000000000042'

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
    logo_url
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'seattle-kubernetes-meetup',
    :'communityID',
    :'categoryID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
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
    event_kind_id,
    event_category_id,
    group_id,
    published,
    starts_at,
    timezone,
    venue_city,
    capacity,
    logo_url
) values (
    :'eventID',
    'KubeCon Seattle 2024',
    'kubecon-seattle-2024',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts',
    'in-person',
    :'eventCategoryID',
    :'groupID',
    true,
    '2024-06-15 09:00:00+00',
    'America/New_York',
    'New York',
    5,
    'https://example.com/event-logo.png'
);

insert into event_attendee (event_id, user_id)
values
    (:'eventID', :'attendee1ID'),
    (:'eventID', :'attendee2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_event_summary should return correct event summary JSON
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
        "group_slug": "seattle-kubernetes-meetup",
        "kind": "in-person",
        "name": "KubeCon Seattle 2024",
        "published": true,
        "slug": "kubecon-seattle-2024",
        "timezone": "America/New_York",
        "group_city": "New York",
        "group_country_code": "US",
        "group_country_name": "United States",
        "group_state": "NY",
        "logo_url": "https://example.com/event-logo.png",
        "starts_at": 1718442000,
        "venue_city": "New York",
        "remaining_capacity": 3
    }'::jsonb,
    'get_event_summary should return correct event summary data as JSON'
);

-- Test: get_event_summary with non-existent event ID should return null
select ok(
    get_event_summary(
        :'communityID'::uuid,
        :'groupID'::uuid,
        '00000000-0000-0000-0000-000000999999'::uuid
    ) is null,
    'get_event_summary with non-existent event ID should return null'
);

-- Test: get_event_summary should return null when group does not match event
select ok(
    get_event_summary(
        :'communityID'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid,
        :'eventID'::uuid
    ) is null,
    'get_event_summary should return null when group does not match event'
);

-- Test: get_event_summary should return null when community does not match event
select ok(
    get_event_summary(
        '00000000-0000-0000-0000-000000000002'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    ) is null,
    'get_event_summary should return null when community does not match event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
