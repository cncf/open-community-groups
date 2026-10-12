-- Tests matching publicly visible events against search filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(28);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5ea70000-0000-0000-0000-000000000001'
\set communityInactiveID '5ea70000-0000-0000-0000-000000000002'
\set communityOtherID '5ea70000-0000-0000-0000-000000000003'
\set eventCanceledID '5ea70000-0000-0000-0000-000000000004'
\set eventCategoryID '5ea70000-0000-0000-0000-000000000005'
\set eventCategoryInactiveID '5ea70000-0000-0000-0000-000000000006'
\set eventCategoryOtherID '5ea70000-0000-0000-0000-000000000007'
\set eventCategoryTalksID '5ea70000-0000-0000-0000-000000000008'
\set eventDeletedID '5ea70000-0000-0000-0000-000000000009'
\set eventHybridID '5ea70000-0000-0000-0000-00000000000a'
\set eventInactiveCommunityID '5ea70000-0000-0000-0000-00000000000b'
\set eventInactiveGroupID '5ea70000-0000-0000-0000-00000000000c'
\set eventLocatedID '5ea70000-0000-0000-0000-00000000000d'
\set eventOnsiteID '5ea70000-0000-0000-0000-00000000000e'
\set eventOtherID '5ea70000-0000-0000-0000-00000000000f'
\set eventTestID '5ea70000-0000-0000-0000-000000000010'
\set eventUnpublishedID '5ea70000-0000-0000-0000-000000000011'
\set eventVirtualID '5ea70000-0000-0000-0000-000000000012'
\set groupCategoryBusinessID '5ea70000-0000-0000-0000-000000000013'
\set groupCategoryID '5ea70000-0000-0000-0000-000000000014'
\set groupCategoryInactiveID '5ea70000-0000-0000-0000-000000000015'
\set groupCategoryOtherID '5ea70000-0000-0000-0000-000000000016'
\set groupInactiveCommunityID '5ea70000-0000-0000-0000-000000000017'
\set groupInactiveID '5ea70000-0000-0000-0000-000000000018'
\set groupNewYorkID '5ea70000-0000-0000-0000-000000000019'
\set groupOtherID '5ea70000-0000-0000-0000-00000000001a'
\set groupSanFranciscoID '5ea70000-0000-0000-0000-00000000001b'
\set regionID '5ea70000-0000-0000-0000-00000000001c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community searched by name
select fx_community(:'communityID', jsonb_build_object('name', 'sem-community'));

-- Inactive community whose events never match
select fx_community(:'communityInactiveID', jsonb_build_object(
    'active', false,
    'name', 'sem-inactive-community'
));

-- Second active community
select fx_community(:'communityOtherID', jsonb_build_object('name', 'sem-other-community'));

-- Event category used by events outside the category filter
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category in the inactive community
select fx_event_category(:'eventCategoryInactiveID', :'communityInactiveID');

-- Event category in the second community
select fx_event_category(:'eventCategoryOtherID', :'communityOtherID');

-- Event category used by event-category filtering
select fx_event_category(:'eventCategoryTalksID', :'communityID', jsonb_build_object(
    'name', 'SEM Talks'
));

-- Group category used by group-category filtering
select fx_group_category(:'groupCategoryBusinessID', :'communityID', jsonb_build_object(
    'name', 'SEM Business'
));

-- Group category used by groups outside the category filter
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category in the inactive community
select fx_group_category(:'groupCategoryInactiveID', :'communityInactiveID');

-- Group category in the second community
select fx_group_category(:'groupCategoryOtherID', :'communityOtherID');

-- Region used by region filtering
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'SEM North America');

-- Group in the inactive community
select fx_group(:'groupInactiveCommunityID', :'communityInactiveID', :'groupCategoryInactiveID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-104.9903 39.7392)'),
    'slug', 'sem-group-inactive-community'
));

-- Inactive group in San Francisco
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'slug', 'sem-group-inactive'
));

-- Business group in New York
select fx_group(:'groupNewYorkID', :'communityID', :'groupCategoryBusinessID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-73.935242 40.73061)'),
    'slug', 'sem-group-ny'
));

-- Group in Chicago in the second community
select fx_group(:'groupOtherID', :'communityOtherID', :'groupCategoryOtherID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-87.6298 41.8781)'),
    'slug', 'sem-group-other'
));

-- Group in San Francisco within the region
select fx_group(:'groupSanFranciscoID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'region_id', :'regionID',
    'slug', 'sem-group-sf',
    'slug_pretty', 'sem-group-sf-pretty'
));

-- Canceled event
select fx_event(:'eventCanceledID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', '2040-03-01 12:00:00+00'
));

-- Deleted event
select fx_event(:'eventDeletedID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'deleted', true,
    'published', false,
    'starts_at', '2040-03-01 15:00:00+00'
));

-- Hybrid event located in London while its group is in San Francisco
select fx_event(:'eventHybridID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'event_kind_id', 'hybrid',
    'location', ST_GeogFromText('POINT(-0.1278 51.5074)'),
    'published', true,
    'starts_at', '2040-03-03 10:00:00+00'
));

-- Event in the inactive community
select fx_event(:'eventInactiveCommunityID', :'groupInactiveCommunityID', :'eventCategoryInactiveID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-03-01 16:00:00+00'
));

-- Event in the inactive group
select fx_event(:'eventInactiveGroupID', :'groupInactiveID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-03-01 17:00:00+00'
));

-- Event located in San Francisco while its group is in New York, starting late in the day
select fx_event(:'eventLocatedID', :'groupNewYorkID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'location', ST_GeogFromText('POINT(-122.4194 37.7749)'),
    'published', true,
    'starts_at', '2040-03-04 18:00:00+00'
));

-- In-person event located only through its San Francisco group
select fx_event(:'eventOnsiteID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'published', true,
    'starts_at', '2040-03-01 10:00:00+00'
));

-- Event in the second community
select fx_event(:'eventOtherID', :'groupOtherID', :'eventCategoryOtherID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-03-05 10:00:00+00'
));

-- Test event
select fx_event(:'eventTestID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-03-01 13:00:00+00',
    'test_event', true
));

-- Unpublished event
select fx_event(:'eventUnpublishedID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'published', false,
    'starts_at', '2040-03-01 14:00:00+00'
));

-- Virtual event tagged for text search
select fx_event(:'eventVirtualID', :'groupSanFranciscoID', :'eventCategoryTalksID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2040-03-02 10:00:00+00',
    'tags', array['docker']
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should compute distances from the event location, falling back to the group location
select results_eq(
    $$
        select event_id, round(distance)
        from search_events_matches('{
            "group": ["sem-group-ny", "sem-group-sf"],
            "kind": ["in-person"],
            "latitude": 40.73061,
            "longitude": -73.935242,
            "sort_by": "distance"
        }'::jsonb)
        order by event_id
    $$,
    format(
        $$
            values
                (%L::uuid, round(st_distance(
                    'POINT(-122.4194 37.7749)'::geography,
                    'POINT(-73.935242 40.73061)'::geography
                ))),
                (%L::uuid, round(st_distance(
                    'POINT(-122.4194 37.7749)'::geography,
                    'POINT(-73.935242 40.73061)'::geography
                )))
        $$,
        :'eventLocatedID',
        :'eventOnsiteID'
    ),
    'Should compute distances from the event location, falling back to the group location'
);

-- Should exclude canceled events
select ok(
    not exists (
        select 1
        from search_events_matches('{}'::jsonb)
        where event_id = :'eventCanceledID'
    ),
    'Should exclude canceled events'
);

-- Should exclude deleted events
select ok(
    not exists (
        select 1
        from search_events_matches('{}'::jsonb)
        where event_id = :'eventDeletedID'
    ),
    'Should exclude deleted events'
);

-- Should exclude events from inactive communities
select ok(
    not exists (
        select 1
        from search_events_matches('{"community": ["sem-inactive-community"]}'::jsonb)
    ),
    'Should exclude events from inactive communities'
);

-- Should exclude events from inactive groups
select ok(
    not exists (
        select 1
        from search_events_matches('{}'::jsonb)
        where event_id = :'eventInactiveGroupID'
    ),
    'Should exclude events from inactive groups'
);

-- Should exclude test events
select ok(
    not exists (
        select 1
        from search_events_matches('{}'::jsonb)
        where event_id = :'eventTestID'
    ),
    'Should exclude test events'
);

-- Should exclude unpublished events
select ok(
    not exists (
        select 1
        from search_events_matches('{}'::jsonb)
        where event_id = :'eventUnpublishedID'
    ),
    'Should exclude unpublished events'
);

-- Should filter events by bbox using the event location, falling back to the group location
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "bbox_ne_lat": 38.0,
            "bbox_ne_lon": -122.0,
            "bbox_sw_lat": 37.0,
            "bbox_sw_lon": -123.0
        }'::jsonb)
    $$,
    array[:'eventLocatedID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by bbox using the event location, falling back to the group location'
);

-- Should filter events by community
select set_eq(
    $$select event_id from search_events_matches('{"community": ["sem-community"]}'::jsonb)$$,
    array[:'eventHybridID', :'eventLocatedID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by community'
);

-- Should filter events by date range
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "date_from": "2040-03-02",
            "date_to": "2040-03-03"
        }'::jsonb)
    $$,
    array[:'eventHybridID', :'eventVirtualID']::uuid[],
    'Should filter events by date range'
);

-- Should filter events by distance using the event location, falling back to the group location
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "distance": 1000,
            "latitude": 37.7749,
            "longitude": -122.4194
        }'::jsonb)
    $$,
    array[:'eventLocatedID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by distance using the event location, falling back to the group location'
);

-- Should filter events by event category
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "event_category": ["SEM-Talks"]
        }'::jsonb)
    $$,
    array[:'eventHybridID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by event category'
);

-- Should filter events by group category
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "group_category": ["SEM-Business"]
        }'::jsonb)
    $$,
    array[:'eventLocatedID']::uuid[],
    'Should filter events by group category'
);

-- Should filter events by group pretty slug
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "group": ["sem-group-sf-pretty"]
        }'::jsonb)
    $$,
    array[:'eventHybridID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by group pretty slug'
);

-- Should filter events by group slug
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "group": ["sem-group-sf"]
        }'::jsonb)
    $$,
    array[:'eventHybridID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by group slug'
);

-- Should filter events by kind
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "kind": ["hybrid", "virtual"]
        }'::jsonb)
    $$,
    array[:'eventHybridID', :'eventVirtualID']::uuid[],
    'Should filter events by kind'
);

-- Should filter events by region
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "region": ["SEM-North-America"]
        }'::jsonb)
    $$,
    array[:'eventHybridID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should filter events by region'
);

-- Should filter events by text search query
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "ts_query": "dock"
        }'::jsonb)
    $$,
    array[:'eventVirtualID']::uuid[],
    'Should filter events by text search query'
);

-- Should include events starting later on the date_to day
select set_eq(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "date_from": "2040-03-04",
            "date_to": "2040-03-04"
        }'::jsonb)
    $$,
    array[:'eventLocatedID']::uuid[],
    'Should include events starting later on the date_to day'
);

-- Should leave distances empty unless sorting by distance
select ok(
    not exists (
        select 1
        from search_events_matches('{
            "community": ["sem-community"],
            "latitude": 37.7749,
            "longitude": -122.4194
        }'::jsonb)
        where distance is not null
    ),
    'Should leave distances empty unless sorting by distance'
);

-- Should match all communities when the community selection is empty
select set_eq(
    $$select event_id from search_events_matches('{"community": []}'::jsonb)$$,
    array[
        :'eventHybridID',
        :'eventLocatedID',
        :'eventOnsiteID',
        :'eventOtherID',
        :'eventVirtualID'
    ]::uuid[],
    'Should match all communities when the community selection is empty'
);

-- Should match all groups when the group selection is empty
select set_eq(
    $$select event_id from search_events_matches('{"community": ["sem-community"], "group": []}'::jsonb)$$,
    array[:'eventHybridID', :'eventLocatedID', :'eventOnsiteID', :'eventVirtualID']::uuid[],
    'Should match all groups when the group selection is empty'
);

-- Should match nothing for a group outside the selected communities
select is_empty(
    $$
        select event_id
        from search_events_matches('{
            "community": ["sem-community"],
            "group": ["sem-group-other"]
        }'::jsonb)
    $$,
    'Should match nothing for a group outside the selected communities'
);

-- Should match nothing for an unknown community
select is_empty(
    $$select event_id from search_events_matches('{"community": ["sem-unknown-community"]}'::jsonb)$$,
    'Should match nothing for an unknown community'
);

-- Should match nothing for an unknown group
select is_empty(
    $$select event_id from search_events_matches('{"group": ["sem-unknown-group"]}'::jsonb)$$,
    'Should match nothing for an unknown group'
);

-- Should return every visible event without filters
select set_eq(
    $$select event_id from search_events_matches('{}'::jsonb)$$,
    array[
        :'eventHybridID',
        :'eventLocatedID',
        :'eventOnsiteID',
        :'eventOtherID',
        :'eventVirtualID'
    ]::uuid[],
    'Should return every visible event without filters'
);

-- Should return the community, group and start date of each match
select results_eq(
    $$
        select community_id, event_id, group_id, starts_at
        from search_events_matches('{"community": ["sem-other-community"]}'::jsonb)
    $$,
    format(
        $$values (%L::uuid, %L::uuid, %L::uuid, '2040-03-05 10:00:00+00'::timestamptz)$$,
        :'communityOtherID',
        :'eventOtherID',
        :'groupOtherID'
    ),
    'Should return the community, group and start date of each match'
);

-- Should return the event's own location, null when located only through its group
select results_eq(
    $$
        select event_id, st_astext(location::geometry)
        from search_events_matches('{
            "bbox_ne_lat": 38.0,
            "bbox_ne_lon": -122.0,
            "bbox_sw_lat": 37.0,
            "bbox_sw_lon": -123.0
        }'::jsonb)
        order by event_id
    $$,
    format(
        $$
            values
                (%L::uuid, 'POINT(-122.4194 37.7749)'),
                (%L::uuid, null),
                (%L::uuid, null)
        $$,
        :'eventLocatedID',
        :'eventOnsiteID',
        :'eventVirtualID'
    ),
    'Should return the event''s own location, null when located only through its group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
