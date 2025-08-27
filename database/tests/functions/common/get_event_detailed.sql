-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set groupInactiveID '00000000-0000-0000-0000-000000000022'
\set eventID '00000000-0000-0000-0000-000000000031'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000032'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000033'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (for testing event detailed function)
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

-- Group category (for organizing groups)
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category (for organizing events)
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech Talks', 'tech-talks', :'communityID');

-- Active group (with location data)
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
    location
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
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326)
);

-- Inactive group (for testing filtering)
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
    :'categoryID',
    false
);

-- Published event (with detailed information)
insert into event (
    event_id,
    name,
    slug,
    description,
    event_kind_id,
    event_category_id,
    group_id,
    published,
    canceled,
    starts_at,
    ends_at,
    timezone,
    timezone_abbr,
    description_short,
    venue_name,
    venue_address,
    venue_city,
    logo_url
) values (
    :'eventID',
    'KubeCon Seattle 2024',
    'kubecon-seattle-2024',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts',
    'hybrid',
    :'eventCategoryID',
    :'groupID',
    true,
    false,
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
    'America/New_York',
    'EST',
    'Annual Kubernetes conference',
    'Convention Center',
    '123 Main St',
    'New York',
    'https://example.com/event-logo.png'
);

-- Unpublished event (for testing visibility)
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

-- Event with inactive group (for testing group status)
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

-- Function returns correct data for published event
select is(
    get_event_detailed('00000000-0000-0000-0000-000000000031'::uuid)::jsonb,
    '{
        "canceled": false,
        "event_id": "00000000-0000-0000-0000-000000000031",
        "group_category_name": "Technology",
        "group_name": "Seattle Kubernetes Meetup",
        "group_slug": "seattle-kubernetes-meetup",
        "kind": "hybrid",
        "name": "KubeCon Seattle 2024",
        "slug": "kubecon-seattle-2024",
        "timezone": "America/New_York",
        "description_short": "Annual Kubernetes conference",
        "ends_at": 1718470800,
        "group_city": "New York",
        "group_country_code": "US",
        "group_country_name": "United States",
        "group_state": "NY",
        "latitude": 40.7128,
        "logo_url": "https://example.com/event-logo.png",
        "longitude": -74.006,
        "starts_at": 1718442000,
        "timezone_abbr": "EST",
        "venue_address": "123 Main St",
        "venue_city": "New York",
        "venue_name": "Convention Center"
    }'::jsonb,
    'get_event_detailed should return correct detailed event data as JSON'
);

-- Function returns null for non-existent event
select ok(
    get_event_detailed('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_event_detailed with non-existent event ID should return null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
