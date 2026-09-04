-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(25);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '0c0e0000-0000-0000-0000-000000000001'
\set community2ID '0c0e0000-0000-0000-0000-000000000002'
\set community3ID '0c0e0000-0000-0000-0000-000000000003'
\set event1ID '0c0e0000-0000-0000-0000-000000000004'
\set event2ID '0c0e0000-0000-0000-0000-000000000005'
\set event3ID '0c0e0000-0000-0000-0000-000000000006'
\set event4ID '0c0e0000-0000-0000-0000-000000000007'
\set event5ID '0c0e0000-0000-0000-0000-000000000008'
\set event6ID '0c0e0000-0000-0000-0000-000000000009'
\set event7ID '0c0e0000-0000-0000-0000-00000000000a'
\set event8ID '0c0e0000-0000-0000-0000-00000000000b'
\set eventCategory1ID '0c0e0000-0000-0000-0000-00000000000c'
\set eventCategory2ID '0c0e0000-0000-0000-0000-00000000000d'
\set eventCategory3ID '0c0e0000-0000-0000-0000-00000000000e'
\set group1ID '0c0e0000-0000-0000-0000-00000000000f'
\set group2ID '0c0e0000-0000-0000-0000-000000000010'
\set group3ID '0c0e0000-0000-0000-0000-000000000011'
\set group4ID '0c0e0000-0000-0000-0000-000000000012'
\set groupCategory1ID '0c0e0000-0000-0000-0000-000000000013'
\set groupCategory2ID '0c0e0000-0000-0000-0000-000000000014'
\set groupCategory3ID '0c0e0000-0000-0000-0000-000000000015'
\set groupCategory4ID '0c0e0000-0000-0000-0000-000000000016'
\set region1ID '0c0e0000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

select fx_community(:'community1ID', jsonb_build_object('name', 'test-community'));

-- Inactive community
select fx_community(:'community3ID', jsonb_build_object(
    'active', false,
    'name', 'inactive-community-search-events'
));

-- Baseline communities, group categories and event categories
select fx_community(:'community2ID');
select fx_group_category(:'groupCategory1ID', :'community1ID');
select fx_group_category(:'groupCategory2ID', :'community2ID');
select fx_group_category(:'groupCategory3ID', :'community3ID');
select fx_event_category(:'eventCategory2ID', :'community2ID');
select fx_event_category(:'eventCategory3ID', :'community3ID');

-- Group category used by group-category filtering
select fx_group_category(:'groupCategory4ID', :'community1ID', jsonb_build_object('name', 'Business'));

-- Event category used by event-category filtering
select fx_event_category(:'eventCategory1ID', :'community1ID', jsonb_build_object('name', 'Tech Talks'));

-- Region
insert into region (region_id, name, community_id)
values
    (:'region1ID', 'North America', :'community1ID');

-- Group
select fx_group(:'group1ID', :'community1ID', :'groupCategory1ID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'region_id', :'region1ID',
    'slug', 'test-group',
    'slug_pretty', 'test-group-pretty',
    'state', 'CA'
));
select fx_group(:'group2ID', :'community1ID', :'groupCategory4ID', jsonb_build_object(
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-73.935242 40.73061)'),
    'state', 'NY'
));
select fx_group(:'group3ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'city', 'Chicago',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-87.6298 41.8781)'),
    'state', 'IL'
));
select fx_group(:'group4ID', :'community3ID', :'groupCategory3ID', jsonb_build_object(
    'city', 'Denver',
    'country_code', 'US',
    'country_name', 'United States',
    'location', ST_GeogFromText('POINT(-104.9903 39.7392)'),
    'state', 'CO'
));

-- Event
select fx_event(:'event1ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '1 day' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '1 day',
    'tags', array['kubernetes', 'cloud'],
    'venue_address', '123 Market St',
    'venue_city', 'San Francisco',
    'venue_name', 'Tech Hub'
));
select fx_event(:'event2ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '2 days' + interval '3 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '2 days',
    'tags', array['docker', 'containers'],
    'venue_city', 'New York',
    'venue_name', 'Online'
));
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

-- Canceled event filtered out from search results
select fx_event(:'event4ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() - interval '1 day' + interval '9 hours',
    'starts_at', now() - interval '1 day',
    'tags', array['tech', 'conference'],
    'venue_address', '789 Congress St',
    'venue_city', 'Boston',
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

-- Event in community 2
select fx_event(:'event6ID', :'group3ID', :'eventCategory2ID', jsonb_build_object(
    'ends_at', now() + interval '5 days' + interval '4 hours',
    'published', true,
    'starts_at', now() + interval '5 days',
    'tags', array['python', 'programming'],
    'venue_address', '555 Lake St',
    'venue_city', 'Chicago',
    'venue_name', 'Tech Center'
));

-- Test event filtered out from search results
select fx_event(:'event7ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'ends_at', now() + interval '6 days' + interval '1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '6 days',
    'tags', array['test'],
    'test_event', true,
    'venue_city', 'Online',
    'venue_name', 'Online'
));

-- Event in inactive community filtered out from search results
select fx_event(:'event8ID', :'group4ID', :'eventCategory3ID', jsonb_build_object(
    'ends_at', now() + interval '7 days' + interval '2 hours',
    'published', true,
    'starts_at', now() + interval '7 days',
    'tags', array['inactive'],
    'venue_address', '321 Main St',
    'venue_city', 'Denver',
    'venue_name', 'Tech Hall'
));

-- ============================================================================
-- TESTS
-- ============================================================================

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

-- Should exclude events from inactive communities
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_events(jsonb_build_object('limit', 10, 'offset', 0))::jsonb->'events'
        ) as e
        where e->>'event_id' = :'event8ID'
    ),
    'Should exclude events from inactive communities'
);

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

-- Should return zero total for non-existing community
select is(
    (
        select (
            search_events(
                jsonb_build_object('community', jsonb_build_array('non-existent-community'), 'limit', 10, 'offset', 0)
            )::jsonb->>'total'
        )::bigint
    ),
    0::bigint,
    'Should return zero total for non-existing community'
);

-- Should return all events when community filter is empty array
select is(
    (select search_events(jsonb_build_object('community', jsonb_build_array(), 'limit', 10, 'offset', 0))::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should return all events when community filter is empty array'
);

-- Should return all events when group filter is empty array
select is(
    (select search_events(jsonb_build_object('group', jsonb_build_array(), 'limit', 10, 'offset', 0))::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should return all events when group filter is empty array'
);

-- Should filter events by kind
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'kind', jsonb_build_array('virtual'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should filter events by kind'
);

-- Should filter events by event category
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'event_category', jsonb_build_array('tech-talks'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by event category'
);

-- Should filter events by group category
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'group_category', jsonb_build_array('business'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by group category'
);

-- Should filter events by region
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'region', jsonb_build_array('north-america'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by region'
);

-- Should filter events by text search query
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'ts_query', 'Docker',
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb
    ),
    'Should filter events by text search query'
);

-- Should filter events by date_from
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'date_from', to_char(current_date + interval '2 days', 'YYYY-MM-DD'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should filter events by date_from'
);

-- Should filter events by distance (event location is used when available, otherwise group location)
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'latitude', 37.7749,
            'longitude', -122.4194,
            'distance', 1000,
            'limit', 10,
            'offset', 0
        )
     )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
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
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
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
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
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
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb,
        get_event_summary(:'community2ID'::uuid, :'group3ID'::uuid, :'event6ID'::uuid)::jsonb
    ),
    'Should sort events by distance ascending'
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

-- Should filter events by group
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'group', jsonb_build_array('test-group'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by group'
);

-- Should filter events by group pretty slug
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
            'group', jsonb_build_array('test-group-pretty'),
            'limit', 10,
            'offset', 0
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event1ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event2ID'::uuid)::jsonb,
        get_event_summary(:'community1ID'::uuid, :'group1ID'::uuid, :'event3ID'::uuid)::jsonb
    ),
    'Should filter events by group pretty slug'
);

-- Should return bbox covering all event locations (or group locations if event location is not set)
select is(
    (select search_events(
        jsonb_build_object(
            'community', jsonb_build_array('test-community'),
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
            'community', jsonb_build_array('test-community'),
            'date_from', to_char(current_date + interval '4 days', 'YYYY-MM-DD'),
            'date_to', to_char(current_date + interval '4 days', 'YYYY-MM-DD'),
            'limit', 10,
            'offset', 0,
            'ts_query', 'Innovation'
        )
    )::jsonb->'events'),
    jsonb_build_array(
        get_event_summary(:'community1ID'::uuid, :'group2ID'::uuid, :'event5ID'::uuid)::jsonb
    ),
    'Should include events that start later on date_to'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
