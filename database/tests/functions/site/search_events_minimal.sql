-- Tests searching the minimal events projection for the explore map and calendar.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5ea90000-0000-0000-0000-000000000001'
\set eventBareID '5ea90000-0000-0000-0000-000000000002'
\set eventCategoryID '5ea90000-0000-0000-0000-000000000003'
\set eventCohostID '5ea90000-0000-0000-0000-000000000004'
\set eventMapGroupOnlyID '5ea90000-0000-0000-0000-000000000005'
\set eventMapInsideID '5ea90000-0000-0000-0000-000000000006'
\set eventMapOutsideID '5ea90000-0000-0000-0000-000000000007'
\set eventMonthAfterID '5ea90000-0000-0000-0000-000000000008'
\set eventMonthBeforeID '5ea90000-0000-0000-0000-000000000009'
\set eventOrderEarlyID '5ea90000-0000-0000-0000-00000000000a'
\set eventOrderLateID '5ea90000-0000-0000-0000-00000000000b'
\set eventOrderTieHighID '5ea90000-0000-0000-0000-00000000000d'
\set eventOrderTieLowID '5ea90000-0000-0000-0000-00000000000c'
\set groupBareID '5ea90000-0000-0000-0000-00000000000e'
\set groupCappedID '5ea90000-0000-0000-0000-00000000000f'
\set groupCategoryID '5ea90000-0000-0000-0000-000000000010'
\set groupCohostOwnerID '5ea90000-0000-0000-0000-000000000011'
\set groupCohostPartnerID '5ea90000-0000-0000-0000-000000000012'
\set groupMapHundredID '5ea90000-0000-0000-0000-000000000013'
\set groupMapID '5ea90000-0000-0000-0000-000000000014'
\set groupMonthID '5ea90000-0000-0000-0000-000000000015'
\set groupOrderID '5ea90000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community searched by name
select fx_community(:'communityID', jsonb_build_object('name', 'sec-community'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group without location or pretty slug
select fx_group(:'groupBareID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'slug', 'sec-bare-group'
));

-- Group hosting more events than the limit
select fx_group(:'groupCappedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(0.5 40.05)'),
    'slug', 'sec-capped-group'
));

-- Group owning the co-hosted event
select fx_group(:'groupCohostOwnerID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'slug', 'sec-cohost-owner-group'
));

-- Group co-hosting the event
select fx_group(:'groupCohostPartnerID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'slug', 'sec-cohost-partner-group'
));

-- Group hosting just over a hundred located events
select fx_group(:'groupMapHundredID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-5.5 43)'),
    'slug', 'sec-map-hundred-group'
));

-- Group located in Madrid with a pretty slug
select fx_group(:'groupMapID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'location', ST_GeogFromText('POINT(-3.7038 40.4168)'),
    'slug', 'sec-map-group',
    'slug_pretty', 'sec-map-pretty'
));

-- Group hosting just over a hundred events in one month
select fx_group(:'groupMonthID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'slug', 'sec-month-group'
));

-- Group hosting the ordered events
select fx_group(:'groupOrderID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'slug', 'sec-order-group'
));

-- Undated event without location in the group without location
select fx_event(:'eventBareID', :'groupBareID', :'eventCategoryID', jsonb_build_object(
    'name', 'SEC Bare Event',
    'published', true,
    'slug', 'sec-bare-event'
));

-- Event co-hosted by a second group
select fx_event(:'eventCohostID', :'groupCohostOwnerID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-09-10 10:00:00+00'
));

-- Event located only through its Madrid group
select fx_event(:'eventMapGroupOnlyID', :'groupMapID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-05-01 10:00:00+00'
));

-- Event located in Madrid
select fx_event(:'eventMapInsideID', :'groupMapID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2040-05-02 12:00:00+00',
    'location', ST_GeogFromText('POINT(-3.7 40.42)'),
    'name', 'SEC Map Inside',
    'published', true,
    'slug', 'sec-map-inside',
    'starts_at', '2040-05-02 10:00:00+00'
));

-- Event located in Barcelona
select fx_event(:'eventMapOutsideID', :'groupMapID', :'eventCategoryID', jsonb_build_object(
    'location', ST_GeogFromText('POINT(2.1734 41.3851)'),
    'published', true,
    'starts_at', '2040-05-03 10:00:00+00'
));

-- Event starting the day after the searched month
select fx_event(:'eventMonthAfterID', :'groupMonthID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-09-01 10:00:00+00'
));

-- Event starting the day before the searched month
select fx_event(:'eventMonthBeforeID', :'groupMonthID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-07-31 10:00:00+00'
));

-- Ordered event starting first
select fx_event(:'eventOrderEarlyID', :'groupOrderID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-06-01 10:00:00+00'
));

-- Ordered event starting last
select fx_event(:'eventOrderLateID', :'groupOrderID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-06-03 10:00:00+00'
));

-- Tied event with the higher event ID, inserted first
select fx_event(:'eventOrderTieHighID', :'groupOrderID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-06-02 10:00:00+00'
));

-- Tied event with the lower event ID, sharing the start date
select fx_event(:'eventOrderTieLowID', :'groupOrderID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2040-06-02 10:00:00+00'
));

-- One more located event than the limit, the last one stretching the extent
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone,
    location,
    starts_at
)
select
    format('5ea90000-0000-0000-0003-%s', lpad(i::text, 12, '0'))::uuid,
    'Capped event',
    :'eventCategoryID',
    'in-person',
    :'groupCappedID',
    'SEC Capped Event ' || i,
    true,
    'sec-capped-event-' || i,
    'UTC',
    case
        when i = 1001 then ST_GeogFromText('POINT(20 60)')
        else ST_SetSRID(ST_MakePoint((i % 100) * 0.01, 40 + (i / 100) * 0.01), 4326)::geography
    end,
    '2041-01-01 00:00:00+00'::timestamptz + i * interval '1 minute'
from generate_series(1, 1001) i;

-- Just over a hundred located events
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone,
    location,
    starts_at
)
select
    format('5ea90000-0000-0000-0001-%s', lpad(i::text, 12, '0'))::uuid,
    'Map event',
    :'eventCategoryID',
    'in-person',
    :'groupMapHundredID',
    'SEC Map Hundred Event ' || i,
    true,
    'sec-map-hundred-event-' || i,
    'UTC',
    ST_SetSRID(ST_MakePoint(-6 + i * 0.01, 43), 4326)::geography,
    '2040-10-01 10:00:00+00'::timestamptz + i * interval '1 hour'
from generate_series(1, 101) i;

-- Just over a hundred events spread over every day of August 2040
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone,
    starts_at
)
select
    format('5ea90000-0000-0000-0002-%s', lpad(i::text, 12, '0'))::uuid,
    'Month event',
    :'eventCategoryID',
    'virtual',
    :'groupMonthID',
    'SEC Month Event ' || i,
    true,
    'sec-month-event-' || i,
    'UTC',
    '2040-08-01 10:00:00+00'::timestamptz
        + ((i - 1) % 31) * interval '1 day'
        + ((i - 1) / 31) * interval '1 hour'
from generate_series(1, 101) i;

-- Approved co-host credit that must not duplicate the event
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    '2040-01-01 00:00:00+00',
    'approved',
    :'eventCohostID',
    :'groupCohostPartnerID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should bound every match beyond the limit
select is(
    search_events_minimal('{
        "group": ["sec-capped-group"],
        "view_mode": "map"
    }'::jsonb, 1000)::jsonb->'bbox',
    '{"ne_lat": 60, "ne_lon": 20, "sw_lat": 40, "sw_lon": 0}'::jsonb,
    'Should bound every match beyond the limit'
);

-- Should bound the events' own locations in map mode
select is(
    search_events_minimal('{
        "group": ["sec-bare-group", "sec-map-group"],
        "view_mode": "map"
    }'::jsonb, 1000)::jsonb->'bbox',
    '{"ne_lat": 41.3851, "ne_lon": 2.1734, "sw_lat": 40.42, "sw_lon": -3.7}'::jsonb,
    'Should bound the events'' own locations in map mode'
);

-- Should cap the events at the limit and flag the result as truncated
select is(
    (
        select jsonb_build_object(
            'items', jsonb_array_length(result->'events'),
            'last_event_id', result->'events'->999->>'event_id',
            'total', result->'total',
            'truncated', result->'truncated'
        )
        from (
            select search_events_minimal('{
                "group": ["sec-capped-group"],
                "view_mode": "map"
            }'::jsonb, 1000)::jsonb as result
        ) as output
    ),
    jsonb_build_object(
        'items', 1000,
        'last_event_id', '5ea90000-0000-0000-0003-000000001000',
        'total', 1001,
        'truncated', true
    ),
    'Should cap the events at the limit and flag the result as truncated'
);

-- Should exclude events located only through their group in map mode
select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events_minimal('{
                "group": ["sec-bare-group", "sec-map-group"],
                "view_mode": "map"
            }'::jsonb, 1000)::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(:'eventMapInsideID', :'eventMapOutsideID'),
    'Should exclude events located only through their group in map mode'
);

-- Should include only events with their own location inside the bbox in map mode
select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events_minimal('{
                "bbox_ne_lat": 41.0,
                "bbox_ne_lon": -3.0,
                "bbox_sw_lat": 40.0,
                "bbox_sw_lon": -4.0,
                "group": ["sec-bare-group", "sec-map-group"],
                "view_mode": "map"
            }'::jsonb, 1000)::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(:'eventMapInsideID'),
    'Should include only events with their own location inside the bbox in map mode'
);

-- Should not require a location in calendar mode
select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events_minimal('{
                "group": ["sec-bare-group", "sec-map-group"],
                "view_mode": "calendar"
            }'::jsonb, 1000)::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(
        :'eventMapGroupOnlyID',
        :'eventMapInsideID',
        :'eventMapOutsideID',
        :'eventBareID'
    ),
    'Should not require a location in calendar mode'
);

-- Should not return a bbox in calendar mode
select is(
    search_events_minimal('{
        "group": ["sec-bare-group", "sec-map-group"],
        "view_mode": "calendar"
    }'::jsonb, 1000)::jsonb->'bbox',
    'null'::jsonb,
    'Should not return a bbox in calendar mode'
);

-- Should order events by start date then event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events_minimal('{
                "group": ["sec-order-group"],
                "view_mode": "calendar"
            }'::jsonb, 1000)::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(
        :'eventOrderEarlyID',
        :'eventOrderTieLowID',
        :'eventOrderTieHighID',
        :'eventOrderLateID'
    ),
    'Should order events by start date then event ID'
);

-- Should return a co-hosted event once
select is(
    (
        select jsonb_agg(event_item->>'event_id')
        from jsonb_array_elements(
            search_events_minimal('{
                "community": ["sec-community"],
                "date_from": "2040-09-10",
                "date_to": "2040-09-10",
                "view_mode": "calendar"
            }'::jsonb, 1000)::jsonb->'events'
        ) as events(event_item)
    ),
    jsonb_build_array(:'eventCohostID'),
    'Should return a co-hosted event once'
);

-- Should return an empty result when nothing matches
select is(
    search_events_minimal('{
        "bbox_ne_lat": -39.0,
        "bbox_ne_lon": -29.0,
        "bbox_sw_lat": -40.0,
        "bbox_sw_lon": -30.0,
        "community": ["sec-community"],
        "view_mode": "map"
    }'::jsonb, 1000)::jsonb,
    '{"events": [], "total": 0, "bbox": null, "truncated": false}'::jsonb,
    'Should return an empty result when nothing matches'
);

-- Should return every match up to the limit for a calendar month
select is(
    (
        select jsonb_build_object(
            'items', jsonb_array_length(result->'events'),
            'late_month_items', (
                select count(*)
                from jsonb_array_elements(result->'events') event_item
                where (event_item->>'starts_at')::bigint >= 2229724800
            ),
            'total', result->'total',
            'truncated', result->'truncated'
        )
        from (
            select search_events_minimal('{
                "date_from": "2040-08-01",
                "date_to": "2040-08-31",
                "group": ["sec-month-group"],
                "view_mode": "calendar"
            }'::jsonb, 1000)::jsonb as result
        ) as output
    ),
    jsonb_build_object(
        'items', 101,
        'late_month_items', 12,
        'total', 101,
        'truncated', false
    ),
    'Should return every match up to the limit for a calendar month'
);

-- Should return every match up to the limit in map mode
select is(
    (
        select jsonb_build_object(
            'items', jsonb_array_length(result->'events'),
            'total', result->'total',
            'truncated', result->'truncated'
        )
        from (
            select search_events_minimal('{
                "bbox_ne_lat": 43.5,
                "bbox_ne_lon": -4.5,
                "bbox_sw_lat": 42.5,
                "bbox_sw_lon": -6.0,
                "group": ["sec-map-hundred-group"],
                "view_mode": "map"
            }'::jsonb, 1000)::jsonb as result
        ) as output
    ),
    jsonb_build_object(
        'items', 101,
        'total', 101,
        'truncated', false
    ),
    'Should return every match up to the limit in map mode'
);

-- Should return the required and optional fields of each event
select is(
    search_events_minimal('{
        "bbox_ne_lat": 41.0,
        "bbox_ne_lon": -3.0,
        "bbox_sw_lat": 40.0,
        "bbox_sw_lon": -4.0,
        "group": ["sec-map-group"],
        "view_mode": "map"
    }'::jsonb, 1000)::jsonb->'events',
    jsonb_build_array(
        jsonb_build_object(
            'community_name', 'sec-community',
            'event_id', :'eventMapInsideID',
            'group_slug', 'sec-map-group',
            'name', 'SEC Map Inside',
            'slug', 'sec-map-inside',

            'ends_at', 2219572800,
            'group_slug_pretty', 'sec-map-pretty',
            'latitude', 40.42,
            'longitude', -3.7,
            'starts_at', 2219565600
        )
    ),
    'Should return the required and optional fields of each event'
);

-- Should strip absent optional fields
select is(
    search_events_minimal('{
        "group": ["sec-bare-group"],
        "view_mode": "calendar"
    }'::jsonb, 1000)::jsonb->'events',
    jsonb_build_array(
        jsonb_build_object(
            'community_name', 'sec-community',
            'event_id', :'eventBareID',
            'group_slug', 'sec-bare-group',
            'name', 'SEC Bare Event',
            'slug', 'sec-bare-event'
        )
    ),
    'Should strip absent optional fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
