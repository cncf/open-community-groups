-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(25);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '0c160000-0000-0000-0000-000000000001'
\set alliance2ID '0c160000-0000-0000-0000-000000000002'
\set alliance3ID '0c160000-0000-0000-0000-000000000003'
\set event1ID '0c160000-0000-0000-0000-000000000004'
\set event2ID '0c160000-0000-0000-0000-000000000005'
\set event3ID '0c160000-0000-0000-0000-000000000006'
\set event4ID '0c160000-0000-0000-0000-000000000007'
\set event5ID '0c160000-0000-0000-0000-000000000008'
\set event6ID '0c160000-0000-0000-0000-000000000009'
\set event7ID '0c160000-0000-0000-0000-00000000000a'
\set event8ID '0c160000-0000-0000-0000-00000000000b'
\set eventCategory1ID '0c160000-0000-0000-0000-00000000000c'
\set eventCategory2ID '0c160000-0000-0000-0000-00000000000d'
\set eventCategory3ID '0c160000-0000-0000-0000-00000000000e'
\set group1ID '0c160000-0000-0000-0000-00000000000f'
\set group2ID '0c160000-0000-0000-0000-000000000010'
\set group3ID '0c160000-0000-0000-0000-000000000011'
\set group4ID '0c160000-0000-0000-0000-000000000012'
\set groupCategory1ID '0c160000-0000-0000-0000-000000000013'
\set groupCategory2ID '0c160000-0000-0000-0000-000000000014'
\set groupCategory3ID '0c160000-0000-0000-0000-000000000015'
\set groupCategory4ID '0c160000-0000-0000-0000-000000000016'
\set region1ID '0c160000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'alliance1ID',
        'test-alliance',
        'Test Alliance',
        'A test alliance',
        'https://example.com/banner_mobile.png',
        'https://example.com/banner.png',
        'https://example.com/logo.png'
    ),
    (
        :'alliance2ID',
        'other-alliance',
        'Other Alliance',
        'Another test alliance',
        'https://example.com/banner_mobile2.png',
        'https://example.com/banner2.png',
        'https://example.com/logo2.png'
    );

-- Inactive alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,

    active
) values (
    :'alliance3ID',
    'inactive-alliance',
    'Inactive Alliance',
    'An inactive test alliance',
    'https://example.com/banner_mobile3.png',
    'https://example.com/banner3.png',
    'https://example.com/logo3.png',

    false
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategory1ID', :'alliance1ID', 'Technology'),
    (:'groupCategory2ID', :'alliance2ID', 'Technology'),
    (:'groupCategory3ID', :'alliance3ID', 'Technology'),
    (:'groupCategory4ID', :'alliance1ID', 'Business');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values
    (:'eventCategory1ID', :'alliance1ID', 'Tech Talks'),
    (:'eventCategory2ID', :'alliance2ID', 'Workshops'),
    (:'eventCategory3ID', :'alliance3ID', 'Workshops');

-- Region
insert into region (region_id, name, alliance_id)
values
    (:'region1ID', 'North America', :'alliance1ID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    slug_pretty,
    alliance_id,
    group_category_id,
    city,
    state,
    country_code,
    country_name,
    logo_url,
    location,
    region_id
)
values (
    :'group1ID',
    'Test Group',
    'test-group',
    'test-group-pretty',
    :'alliance1ID',
    :'groupCategory1ID',
    'San Francisco',
    'CA',
    'US',
    'United States',
    'https://example.com/group-logo.png',
    ST_GeogFromText('POINT(-122.4194 37.7749)'),
    :'region1ID'
), (
    :'group2ID',
    'Cloud Group',
    'cloud-group',
    null,
    :'alliance1ID',
    :'groupCategory4ID',
    'New York',
    'NY',
    'US',
    'United States',
    'https://example.com/cloud-group.png',
    ST_GeogFromText('POINT(-73.935242 40.73061)'),
    null
), (
    :'group3ID',
    'Other Group',
    'other-group',
    null,
    :'alliance2ID',
    :'groupCategory2ID',
    'Chicago',
    'IL',
    'US',
    'United States',
    'https://example.com/other-group.png',
    ST_GeogFromText('POINT(-87.6298 41.8781)'),
    null
), (
    :'group4ID',
    'Inactive Alliance Group',
    'inactive-alliance-group',
    null,
    :'alliance3ID',
    :'groupCategory3ID',
    'Denver',
    'CO',
    'US',
    'United States',
    'https://example.com/inactive-alliance-group.png',
    ST_GeogFromText('POINT(-104.9903 39.7392)'),
    null
);

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    test_event,
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
) values (
    :'event1ID',
    'Kubernetes Workshop',
    'kubernetes-workshop',
    'Learn Kubernetes',
    false,
    'K8s intro workshop',
    'UTC',
    :'eventCategory1ID',
    'in-person',
    :'group1ID',
    true,
    now() + interval '1 day',
    now() + interval '1 day' + interval '2 hours',
    array['kubernetes', 'cloud'],
    'San Francisco',
    'Tech Hub',
    '123 Market St',
    'https://example.com/k8s-workshop.png',
    false,
    null
), (
    :'event2ID',
    'Docker Training',
    'docker-training',
    'Docker fundamentals',
    false,
    'Docker basics',
    'UTC',
    :'eventCategory1ID',
    'virtual',
    :'group1ID',
    true,
    now() + interval '2 days',
    now() + interval '2 days' + interval '3 hours',
    array['docker', 'containers'],
    'New York',
    'Online',
    null,
    'https://example.com/docker-training.png',
    false,
    null
), (
    :'event3ID',
    'Cloud Summit',
    'cloud-summit',
    'Annual cloud conference',
    false,
    'Cloud conf 2026',
    'UTC',
    :'eventCategory1ID',
    'hybrid',
    :'group1ID',
    true,
    now() + interval '3 days',
    now() + interval '3 days' + interval '7 hours',
    array['cloud', 'aws'],
    'London',
    'Convention Center',
    '456 Oxford St',
    'https://example.com/cloud-summit.png',
    false,
    null
),
-- Canceled event (should be filtered out from search results)
(
    :'event4ID',
    'Canceled Tech Conference',
    'canceled-tech-conf',
    'This event was canceled',
    false,
    'Canceled conf',
    'UTC',
    :'eventCategory1ID',
    'in-person',
    :'group1ID',
    false,
    now() - interval '1 day',
    now() - interval '1 day' + interval '9 hours',
    array['tech', 'conference'],
    'Boston',
    'Convention Center',
    '789 Congress St',
    'https://example.com/canceled-conf.png',
    true,
    null
),
-- Event with its own location (different from group location - group is in New York, event is in San Francisco)
(
    :'event5ID',
    'Cloud Innovation Summit',
    'cloud-innovation-summit',
    'Cloud innovations',
    false,
    'Cloud summit',
    'UTC',
    :'eventCategory1ID',
    'in-person',
    :'group2ID',
    true,
    now() + interval '4 days',
    now() + interval '4 days' + interval '7 hours',
    array['cloud', 'innovation'],
    'San Francisco',
    'Innovation Center',
    '123 Tech Ave',
    'https://example.com/cloud-innovation.png',
    false,
    ST_GeogFromText('POINT(-122.4194 37.7749)')
),
-- Event in alliance 2
(
    :'event6ID',
    'Python Workshop',
    'python-workshop',
    'Learn Python',
    false,
    'Python basics',
    'UTC',
    :'eventCategory2ID',
    'in-person',
    :'group3ID',
    true,
    now() + interval '5 days',
    now() + interval '5 days' + interval '4 hours',
    array['python', 'programming'],
    'Chicago',
    'Tech Center',
    '555 Lake St',
    'https://example.com/python-workshop.png',
    false,
    null
),
-- Test event (should be filtered out from search results)
(
    :'event7ID',
    'Test Fixture Event',
    'test-fixture-event',
    'Internal test event',
    true,
    'Test fixture',
    'UTC',
    :'eventCategory1ID',
    'virtual',
    :'group1ID',
    true,
    now() + interval '6 days',
    now() + interval '6 days' + interval '1 hour',
    array['test'],
    'Online',
    'Online',
    null,
    'https://example.com/test-fixture.png',
    false,
    null
),
-- Event in inactive alliance (should be filtered out from search results)
(
    :'event8ID',
    'Inactive Alliance Event',
    'inactive-alliance-event',
    'Event in inactive alliance',
    false,
    'Inactive alliance event',
    'UTC',
    :'eventCategory3ID',
    'in-person',
    :'group4ID',
    true,
    now() + interval '7 days',
    now() + interval '7 days' + interval '2 hours',
    array['inactive'],
    'Denver',
    'Tech Hall',
    '321 Main St',
    'https://example.com/inactive-alliance-event.png',
    false,
    null
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return all published events without filters
select is(
    (select search_events(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'alliance2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should return all published events without filters'
);

-- Should exclude test events from total counts
select is(
    (
        select (
            search_events(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->>'total'
        )::bigint
    ),
    5::bigint,
    'Should exclude test events from total counts'
);

-- Should exclude events from inactive alliances
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_events(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'events'
        ) as e
        where e->>'event_id' = :'event8ID'
    ),
    'Should exclude events from inactive alliances'
);

-- Should filter events by alliance
select is(
    (select search_events(
        jsonb_build_object('alliance', jsonb_build_array('test-alliance'), 'limit', 10, 'offset', 0)
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by alliance'
);

-- Should return events in ascending order when sort_direction is asc
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'limit', 10,
            'offset', 0,
            'sort_direction', 'asc'
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should return events in ascending order when sort_direction is asc'
);

-- Should return events in descending order when sort_direction is desc
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'limit', 10,
            'offset', 0,
            'sort_direction', 'desc'
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should return events in descending order when sort_direction is desc'
);

-- Should return correct total count
select is(
    (
        select (
            search_events(jsonb_build_object('alliance', jsonb_build_array('test-alliance'), 'limit', 10, 'offset', 0))::jsonb->>'total'
        )::bigint
    ),
    4::bigint,
    'Should return correct total count'
);

-- Should return zero total for non-existing alliance
select is(
    (
        select (
            search_events(
                jsonb_build_object('alliance', jsonb_build_array('non-existent-alliance'), 'limit', 10, 'offset', 0)
            )::jsonb->>'total'
        )::bigint
    ),
    0::bigint,
    'Should return zero total for non-existing alliance'
);

-- Should return all events when alliance filter is empty array
select is(
    (select search_events(jsonb_build_object('alliance', jsonb_build_array(), 'limit', 10, 'offset', 0))::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'alliance2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should return all events when alliance filter is empty array'
);

-- Should return all events when group filter is empty array
select is(
    (select search_events(jsonb_build_object('group', jsonb_build_array(), 'limit', 10, 'offset', 0))::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'alliance2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should return all events when group filter is empty array'
);

-- Should filter events by kind
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'kind', jsonb_build_array('virtual'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should filter events by kind'
);

-- Should filter events by event category
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'event_category', jsonb_build_array('tech-talks'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by event category'
);

-- Should filter events by group category
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'group_category', jsonb_build_array('business'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by group category'
);

-- Should filter events by region
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'region', jsonb_build_array('north-america'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by region'
);

-- Should filter events by text search query
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'ts_query', 'Docker',
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should filter events by text search query'
);

-- Should filter events by date_from
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'date_from', to_char(current_date + interval '2 days', 'YYYY-MM-DD'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by date_from'
);

-- Should filter events by distance (event location is used when available, otherwise group location)
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'latitude', 37.7749,
            'longitude', -122.4194,
            'distance', 1000,
            'limit', 10,
            'offset', 0
        )
     )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by distance (event location is used when available, otherwise group location)'
);

-- Should filter events by bbox
select is(
    (select search_events(
        jsonb_build_object(
            'bbox_ne_lat', 38.0,
            'bbox_ne_lon', -122.0,
            'bbox_sw_lat', 37.0,
            'bbox_sw_lon', -123.0,
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by bbox'
);

-- Should sort events by distance
select is(
    (select search_events(
        jsonb_build_object(
            'latitude', 37.7749,
            'longitude', -122.4194,
            'sort_by', 'distance',
            'sort_direction', 'desc',
            'limit', 10,
            'offset', 0
        )
     )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should sort events by distance'
);

-- Should sort events by distance ascending
select is(
    (select search_events(
        jsonb_build_object(
            'latitude', 37.7749,
            'longitude', -122.4194,
            'sort_by', 'distance',
            'sort_direction', 'asc',
            'limit', 10,
            'offset', 0
        )
     )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'alliance2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should sort events by distance ascending'
);

-- Should paginate results correctly
select is(
    (select search_events(
        jsonb_build_object('alliance', jsonb_build_array('test-alliance'), 'limit', 1, 'offset', 1)
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should paginate results correctly'
);

-- Should filter events by group
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'group', jsonb_build_array('test-group'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by group'
);

-- Should filter events by group pretty slug
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'group', jsonb_build_array('test-group-pretty'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'alliance1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by group pretty slug'
);

-- Should return bbox covering all event locations (or group locations if event location is not set)
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'include_bbox', true,
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'bbox'),
    '{"ne_lat": 37.7749, "ne_lon": -122.4194, "sw_lat": 37.7749, "sw_lon": -122.4194}'::jsonb,
    'Should return bbox covering all event locations (or group locations if event location is not set)'
);

-- Should include events that start later on date_to
select is(
    (select search_events(
        jsonb_build_object(
            'alliance', jsonb_build_array('test-alliance'),
            'date_from', to_char(current_date + interval '4 days', 'YYYY-MM-DD'),
            'date_to', to_char(current_date + interval '4 days', 'YYYY-MM-DD'),
            'limit', 10,
            'offset', 0,
            'ts_query', 'Innovation'
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'alliance1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should include events that start later on date_to'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
