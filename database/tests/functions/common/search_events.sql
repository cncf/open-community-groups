-- Tests searching events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '0c0e0000-0000-0000-0000-000000000001'
\set community2ID '0c0e0000-0000-0000-0000-000000000002'
\set event1ID '0c0e0000-0000-0000-0000-000000000004'
\set event2ID '0c0e0000-0000-0000-0000-000000000005'
\set event3ID '0c0e0000-0000-0000-0000-000000000006'
\set event5ID '0c0e0000-0000-0000-0000-000000000008'
\set event6ID '0c0e0000-0000-0000-0000-000000000009'
\set eventCategory1ID '0c0e0000-0000-0000-0000-00000000000c'
\set eventCategory2ID '0c0e0000-0000-0000-0000-00000000000d'
\set group1ID '0c0e0000-0000-0000-0000-00000000000f'
\set group2ID '0c0e0000-0000-0000-0000-000000000010'
\set group3ID '0c0e0000-0000-0000-0000-000000000011'
\set groupCategory1ID '0c0e0000-0000-0000-0000-000000000013'
\set groupCategory2ID '0c0e0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community searched by name
select fx_community(:'community1ID', jsonb_build_object('name', 'test-community'));

-- Second community
select fx_community(:'community2ID');

-- Event category in the first community
select fx_event_category(:'eventCategory1ID', :'community1ID');

-- Event category in the second community
select fx_event_category(:'eventCategory2ID', :'community2ID');

-- Group category in the first community
select fx_group_category(:'groupCategory1ID', :'community1ID');

-- Group category in the second community
select fx_group_category(:'groupCategory2ID', :'community2ID');

-- Group in San Francisco
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'slug', 'test-group',
    'state', 'CA'
));

-- Group in New York
select fx_group(:'group2ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-73.935242 40.73061)'),
    'state', 'NY'
));

-- Group in Chicago in the second community
select fx_group(:'group3ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'city', 'Chicago',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-87.6298 41.8781)'),
    'state', 'IL'
));

-- In-person event located through its San Francisco group
select fx_event(:'event1ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '1 day' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '1 day',
    'tags', array['kubernetes', 'cloud'],
    'venue_address', '123 Market St',
    'venue_city', 'San Francisco',
    'venue_name', 'Tech Hub'
));

-- Virtual event located through its San Francisco group
select fx_event(:'event2ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '2 days' + interval '3 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '2 days',
    'tags', array['docker', 'containers'],
    'venue_city', 'New York',
    'venue_name', 'Online'
));

-- Hybrid event located through its San Francisco group
select fx_event(:'event3ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '3 days' + interval '7 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'starts_at', now() + interval '3 days',
    'tags', array['cloud', 'aws'],
    'venue_address', '456 Oxford St',
    'venue_city', 'London',
    'venue_name', 'Convention Center'
));

-- Event with its own location
select fx_event(:'event5ID', :'group2ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '4 days' + interval '7 hours',
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'published', true,
    'starts_at', now() + interval '4 days',
    'tags', array['cloud', 'innovation'],
    'venue_address', '123 Tech Ave',
    'venue_city', 'San Francisco',
    'venue_name', 'Innovation Center'
));

-- Event located through its Chicago group in the second community
select fx_event(:'event6ID', :'group3ID', :'eventCategory2ID', jsonb_build_object(
    'ends_at', now() + interval '5 days' + interval '4 hours',
    'published', true,
    'starts_at', now() + interval '5 days',
    'tags', array['python', 'programming'],
    'venue_address', '555 Lake St',
    'venue_city', 'Chicago',
    'venue_name', 'Tech Center'
));

-- Approved co-host credit that must not duplicate owner-scoped search results
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    current_timestamp,
    'approved',
    :'event1ID',
    :'group2ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should filter events by community
select is(
    (select search_events(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 10, 'offset', 0)
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by community'
);

-- Should match events located only through their group within the bbox
select is(
    (select search_events(
        jsonb_build_object(
            'bbox_ne_lat', 42.5,
            'bbox_ne_lon', -87.0,
            'bbox_sw_lat', 41.0,
            'bbox_sw_lon', -88.5,
            'limit', 10,
            'offset', 0
        )
    )::jsonb),
    jsonb_build_object(
        'events', jsonb_build_array(
            get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
        ),
        'total', 1
    ),
    'Should match events located only through their group within the bbox'
);

-- Should paginate results correctly
select is(
    (select search_events(
        jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 1, 'offset', 1)
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should paginate results correctly'
);

-- Should return all published events without filters
select is(
    (select search_events(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should return all published events without filters'
);

-- Should return correct total count
select is(
    (
        select (
            search_events(jsonb_build_object('community', jsonb_build_array('test-community'), 'limit', 10, 'offset', 0))::jsonb->>'total'
        )::bigint
    ),
    4::bigint,
    'Should return correct total count'
);

-- Should return events in ascending order when sort_direction is asc
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'limit', 10,
            'offset', 0,
            'sort_direction', 'asc'
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should return events in ascending order when sort_direction is asc'
);

-- Should return events in descending order when sort_direction is desc
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'limit', 10,
            'offset', 0,
            'sort_direction', 'desc'
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb
    ),
    'Should return events in descending order when sort_direction is desc'
);

-- Should show a co-hosted event once under its owner
select is(
    (
        select count(*)::int
        from jsonb_array_elements(
            search_events(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'events'
        ) event_item
        where event_item->>'event_id' = :'event1ID'
        and event_item->>'group_slug' = 'test-group'
    ),
    1,
    'Should show a co-hosted event once under its owner'
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
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should sort events by distance ascending'
);

-- Should sort events by distance descending
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
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should sort events by distance descending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
