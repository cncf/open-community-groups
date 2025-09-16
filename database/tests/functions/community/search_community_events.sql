-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'

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
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name, logo_url, location)
values (:'group1ID', 'Test Group', 'test-group', :'communityID', :'category1ID',
        'San Francisco', 'CA', 'US', 'United States', 'https://example.com/group-logo.png',
        ST_GeogFromText('POINT(-122.4194 37.7749)'));

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategory1ID', 'Tech Talks', 'tech-talks', :'communityID');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    starts_at,
    ends_at,
    tags,
    venue_city,
    venue_name,
    venue_address,
    logo_url,
    canceled
) values
    (:'event1ID', 'Kubernetes Workshop', 'kubernetes-workshop', 'Learn Kubernetes', 'K8s intro workshop', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2026-02-01 10:00:00+00', '2026-02-01 12:00:00+00', array['kubernetes', 'cloud'],
     'San Francisco', 'Tech Hub', '123 Market St', 'https://example.com/k8s-workshop.png', false),
    (:'event2ID', 'Docker Training', 'docker-training', 'Docker fundamentals', 'Docker basics', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-02 10:00:00+00', '2026-02-02 13:00:00+00', array['docker', 'containers'],
     'New York', 'Online', null, 'https://example.com/docker-training.png', false),
    (:'event3ID', 'Cloud Summit', 'cloud-summit', 'Annual cloud conference', 'Cloud conf 2026', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', true,
     '2026-02-03 10:00:00+00', '2026-02-03 17:00:00+00', array['cloud', 'aws'],
     'London', 'Convention Center', '456 Oxford St', 'https://example.com/cloud-summit.png', false),
    -- Canceled event (should be filtered out from search results)
    (:'event4ID', 'Canceled Tech Conference', 'canceled-tech-conf', 'This event was canceled', 'Canceled conf', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', false,
     '2026-01-20 09:00:00+00', '2026-01-20 18:00:00+00', array['tech', 'conference'],
     'Boston', 'Convention Center', '789 Congress St', 'https://example.com/canceled-conf.png', true);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: search_community_events without filters should return all events with expected JSON
select is(
    (select events from search_community_events(:'communityID'::uuid, '{}'::jsonb))::jsonb,
    jsonb_build_array(
        get_event_detailed(:'event1ID'::uuid)::jsonb,
        get_event_detailed(:'event2ID'::uuid)::jsonb,
        get_event_detailed(:'event3ID'::uuid)::jsonb
    ),
    'search_community_events without filters returns all published events with correct JSON structure'
);

-- Test: search_community_events should return correct total count
select is(
    (select total from search_community_events(:'communityID'::uuid, '{}'::jsonb)),
    3::bigint,
    'search_community_events returns correct total count'
);

-- Test: search_community_events with non-existing community should return zero total
select is(
    (select total from search_community_events('00000000-0000-0000-0000-999999999999'::uuid, '{}'::jsonb)),
    0::bigint,
    'search_community_events with non-existing community returns zero total'
);

-- Test: search_community_events kind filter should return only Docker Training JSON
select is(
    (select events from search_community_events(:'communityID'::uuid, '{"kind":["virtual"]}'::jsonb))::jsonb,
    jsonb_build_array(get_event_detailed(:'event2ID'::uuid)::jsonb),
    'search_community_events kind filter returns expected event JSON'
);

-- Test: search_community_events ts_query filter should return only Docker Training JSON
select is(
    (select events from search_community_events(:'communityID'::uuid, '{"ts_query":"Docker"}'::jsonb))::jsonb,
    jsonb_build_array(get_event_detailed(:'event2ID'::uuid)::jsonb),
    'search_community_events ts_query filter returns expected event JSON'
);

-- Test: search_community_events date_from should return remaining 2 events JSON
select is(
    (select events from search_community_events(:'communityID'::uuid, '{"date_from":"2026-02-02"}'::jsonb))::jsonb,
    jsonb_build_array(
        get_event_detailed(:'event2ID'::uuid)::jsonb,
        get_event_detailed(:'event3ID'::uuid)::jsonb
    ),
    'search_community_events date_from returns expected events JSON'
);

-- Test: search_community_events distance filter should return expected events JSON in SF
select is(
    (select events from search_community_events(
        :'communityID'::uuid,
        '{"latitude":37.7749, "longitude":-122.4194, "distance":1000}'::jsonb
     ))::jsonb,
    jsonb_build_array(
        get_event_detailed(:'event1ID'::uuid)::jsonb,
        get_event_detailed(:'event2ID'::uuid)::jsonb,
        get_event_detailed(:'event3ID'::uuid)::jsonb
    ),
    'search_community_events distance filter returns expected events JSON in SF'
);

-- Test: search_community_events pagination should return second item JSON
select is(
    (select events from search_community_events(:'communityID'::uuid, '{"limit":1, "offset":1}'::jsonb))::jsonb,
    '[
        {
            "canceled": false,
            "event_id": "00000000-0000-0000-0000-000000000042",
            "kind": "virtual",
            "name": "Docker Training",
            "published": true,
            "slug": "docker-training",
            "timezone": "UTC",
            "description_short": "Docker basics",
            "ends_at": 1770037200,
            "group_category_name": "Technology",
            "group_city": "San Francisco",
            "group_country_code": "US",
            "group_country_name": "United States",
            "group_name": "Test Group",
            "group_slug": "test-group",
            "group_state": "CA",
            "latitude": 37.7749,
            "logo_url": "https://example.com/docker-training.png",
            "longitude": -122.4194,
            "starts_at": 1770026400,
            "venue_city": "New York",
            "venue_name": "Online"
        }
    ]'::jsonb,
    'search_community_events pagination returns expected event JSON'
);

-- Test: search_community_events include_bbox should return bbox at group location
select is(
    (select bbox from search_community_events(:'communityID'::uuid, '{"include_bbox":true}'::jsonb))::jsonb,
    '{"ne_lat": 37.7749, "ne_lon": -122.4194, "sw_lat": 37.7749, "sw_lon": -122.4194}'::jsonb,
    'search_community_events include_bbox returns expected bbox at group location'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
