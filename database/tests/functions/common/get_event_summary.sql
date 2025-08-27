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
\set eventID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (for testing event summary function)
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

-- Group (with location data)
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

-- Published event (for summary testing)
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
    timezone_abbr,
    venue_city,
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
    'EST',
    'New York',
    'https://example.com/event-logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Function returns correct summary data
select is(
    get_event_summary('00000000-0000-0000-0000-000000000031'::uuid)::jsonb,
    '{
        "event_id": "00000000-0000-0000-0000-000000000031",
        "group_name": "Seattle Kubernetes Meetup",
        "group_slug": "seattle-kubernetes-meetup",
        "kind": "in-person",
        "name": "KubeCon Seattle 2024",
        "slug": "kubecon-seattle-2024",
        "timezone": "America/New_York",
        "group_city": "New York",
        "group_country_code": "US",
        "group_country_name": "United States",
        "group_state": "NY",
        "logo_url": "https://example.com/event-logo.png",
        "starts_at": 1718442000,
        "timezone_abbr": "EST",
        "venue_city": "New York"
    }'::jsonb,
    'get_event_summary should return correct event summary data as JSON'
);

-- Function returns null for non-existent event

select ok(
    get_event_summary('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'get_event_summary with non-existent event ID should return null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
