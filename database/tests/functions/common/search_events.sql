-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set event3ID '00000000-0000-0000-0000-000000000043'
\set event4ID '00000000-0000-0000-0000-000000000044'
\set event5ID '00000000-0000-0000-0000-000000000045'
\set eventCategory1ID '00000000-0000-0000-0000-000000000021'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, city, state, country_code, country_name, logo_url, location)
values
    (:'group1ID', 'Test Group', 'test-group', :'communityID', :'category1ID',
     'San Francisco', 'CA', 'US', 'United States', 'https://example.com/group-logo.png',
     ST_GeogFromText('POINT(-122.4194 37.7749)')),
    (:'group2ID', 'Cloud Group', 'cloud-group', :'communityID', :'category1ID',
     'New York', 'NY', 'US', 'United States', 'https://example.com/cloud-group.png',
     ST_GeogFromText('POINT(-73.935242 40.73061)'));

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
    canceled,

    location
) values
    (:'event1ID', 'Kubernetes Workshop', 'kubernetes-workshop', 'Learn Kubernetes', 'K8s intro workshop', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', true,
     '2026-02-01 10:00:00+00', '2026-02-01 12:00:00+00', array['kubernetes', 'cloud'],
     'San Francisco', 'Tech Hub', '123 Market St', 'https://example.com/k8s-workshop.png', false,
     null),
    (:'event2ID', 'Docker Training', 'docker-training', 'Docker fundamentals', 'Docker basics', 'UTC',
     :'eventCategory1ID', 'virtual', :'group1ID', true,
     '2026-02-02 10:00:00+00', '2026-02-02 13:00:00+00', array['docker', 'containers'],
     'New York', 'Online', null, 'https://example.com/docker-training.png', false,
     null),
    (:'event3ID', 'Cloud Summit', 'cloud-summit', 'Annual cloud conference', 'Cloud conf 2026', 'UTC',
     :'eventCategory1ID', 'hybrid', :'group1ID', true,
     '2026-02-03 10:00:00+00', '2026-02-03 17:00:00+00', array['cloud', 'aws'],
     'London', 'Convention Center', '456 Oxford St', 'https://example.com/cloud-summit.png', false,
     null),
    -- Canceled event (should be filtered out from search results)
    (:'event4ID', 'Canceled Tech Conference', 'canceled-tech-conf', 'This event was canceled', 'Canceled conf', 'UTC',
     :'eventCategory1ID', 'in-person', :'group1ID', false,
     '2026-01-20 09:00:00+00', '2026-01-20 18:00:00+00', array['tech', 'conference'],
     'Boston', 'Convention Center', '789 Congress St', 'https://example.com/canceled-conf.png', true,
     null),
    -- Event with its own location (different from group location - group is in New York, event is in San Francisco)
    (:'event5ID', 'Cloud Innovation Summit', 'cloud-innovation-summit', 'Cloud innovations', 'Cloud summit', 'UTC',
     :'eventCategory1ID', 'in-person', :'group2ID', true,
     '2026-02-04 10:00:00+00', '2026-02-04 17:00:00+00', array['cloud', 'innovation'],
     'San Francisco', 'Innovation Center', '123 Tech Ave', 'https://example.com/cloud-innovation.png', false,
     ST_GeogFromText('POINT(-122.4194 37.7749)'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all published events without filters
select is(
    (select events from search_events(jsonb_build_object('community', jsonb_build_array(:'communityID'))))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should return all published events without filters'
);

-- Should return events in ascending order when sort_direction is asc
select is(
    (select events from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'sort_direction', 'asc')
    ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should return events in ascending order when sort_direction is asc'
);

-- Should return events in descending order when sort_direction is desc
select is(
    (select events from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'sort_direction', 'desc')
    ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should return events in descending order when sort_direction is desc'
);

-- Should return correct total count
select is(
    (select total from search_events(jsonb_build_object('community', jsonb_build_array(:'communityID')))),
    4::bigint,
    'Should return correct total count'
);

-- Should return zero total for non-existing community
select is(
    (select total from search_events(jsonb_build_object('community', jsonb_build_array('00000000-0000-0000-0000-999999999999')))),
    0::bigint,
    'Should return zero total for non-existing community'
);

-- Should filter events by kind
select is(
    (select events from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'kind', jsonb_build_array('virtual'))
    ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should filter events by kind'
);

-- Should filter events by text search query
select is(
    (select events from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'ts_query', 'Docker')
    ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should filter events by text search query'
);

-- Should filter events by date_from
select is(
    (select events from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'date_from', '2026-02-02')
    ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by date_from'
);

-- Should filter events by distance (event location is used when available, otherwise group location)
select is(
    (select events from search_events(
        jsonb_build_object(
            'community', jsonb_build_array(:'communityID'),
            'latitude', 37.7749,
            'longitude', -122.4194,
            'distance', 1000
        )
     ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by distance (event location is used when available, otherwise group location)'
);

-- Should paginate results correctly
select is(
    (select events from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'limit', 1, 'offset', 1)
    ))::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should paginate results correctly'
);

-- Should filter events by group
select is(
    (
        select events
        from search_events(
            jsonb_build_object(
                'community', jsonb_build_array(:'communityID'),
                'group', jsonb_build_array(:'group1ID')
            )
        )
    )::jsonb,
    jsonb_build_array(
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'communityID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by group'
);

-- Should return bbox covering all event locations (or group locations if event location is not set)
select is(
    (select bbox from search_events(
        jsonb_build_object('community', jsonb_build_array(:'communityID'), 'include_bbox', true)
    ))::jsonb,
    '{"ne_lat": 37.7749, "ne_lon": -122.4194, "sw_lat": 37.7749, "sw_lon": -122.4194}'::jsonb,
    'Should return bbox covering all event locations (or group locations if event location is not set)'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
