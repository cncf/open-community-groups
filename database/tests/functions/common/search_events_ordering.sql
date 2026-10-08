-- Tests the deterministic ordering and pagination of searched events.
-- Split from search_events.sql because these scenarios add searchable events
-- that would change the base file's unfiltered results and totals.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c0f0000-0000-0000-0000-000000000001'
\set eventCategoryID '0c0f0000-0000-0000-0000-000000000002'
\set eventFarID '0c0f0000-0000-0000-0000-000000000003'
\set eventLaterID '0c0f0000-0000-0000-0000-000000000004'
\set eventNoLocationID '0c0f0000-0000-0000-0000-000000000005'
\set eventTie1ID '0c0f0000-0000-0000-0000-000000000006'
\set eventTie2ID '0c0f0000-0000-0000-0000-000000000007'
\set eventTie3ID '0c0f0000-0000-0000-0000-000000000008'
\set eventUndatedID '0c0f0000-0000-0000-0000-000000000009'
\set groupCategoryID '0c0f0000-0000-0000-0000-00000000000a'
\set groupLocatedID '0c0f0000-0000-0000-0000-00000000000b'
\set groupUndatedID '0c0f0000-0000-0000-0000-00000000000c'
\set groupUnlocatedID '0c0f0000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community searched by name
select fx_community(:'communityID', jsonb_build_object('name', 'ordering-community'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group located in Seattle
select fx_group(:'groupLocatedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'slug', 'ordering-located-group'
));

-- Group hosting the undated event
select fx_group(:'groupUndatedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug', 'ordering-undated-group'
));

-- Group without a location
select fx_group(:'groupUnlocatedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug', 'ordering-unlocated-group'
));

-- Event located in Portland starting before the tied events
select fx_event(:'eventFarID', :'groupLocatedID', :'eventCategoryID', jsonb_build_object(
    'location', ST_GeogFromText('POINT(-122.6765 45.5231)'),
    'published', true,
    'starts_at', now() + interval '9 days'
));

-- Event at the group location starting after the tied events
select fx_event(:'eventLaterID', :'groupLocatedID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '11 days'
));

-- Event without any location starting first
select fx_event(:'eventNoLocationID', :'groupUnlocatedID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '8 days'
));

-- First event sharing the tied start time and location
select fx_event(:'eventTie1ID', :'groupLocatedID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '10 days'
));

-- Second event sharing the tied start time and location
select fx_event(:'eventTie2ID', :'groupLocatedID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '10 days'
));

-- Third event sharing the tied start time and location
select fx_event(:'eventTie3ID', :'groupLocatedID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '10 days'
));

-- Published event without a start date
select fx_event(:'eventUndatedID', :'groupUndatedID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include undated events in unbounded searches
select ok(
    exists (
        select 1
        from jsonb_array_elements(
            search_events(jsonb_build_object(
                'community', jsonb_build_array('ordering-community'),
                'limit', 10,
                'offset', 0
            ))::jsonb->'events'
        ) event_item
        where event_item->>'event_id' = :'eventUndatedID'
    ),
    'Should include undated events in unbounded searches'
);

-- Should order equal distances by start time then event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events(jsonb_build_object(
                'community', jsonb_build_array('ordering-community'),
                'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
                'latitude', 47.6062,
                'limit', 10,
                'longitude', -122.3321,
                'offset', 0,
                'sort_by', 'distance',
                'sort_direction', 'asc'
            ))::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(
        :'eventTie1ID',
        :'eventTie2ID',
        :'eventTie3ID',
        :'eventLaterID',
        :'eventFarID',
        :'eventNoLocationID'
    ),
    'Should order equal distances by start time then event ID when sorting by ascending distance'
);

select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events(jsonb_build_object(
                'community', jsonb_build_array('ordering-community'),
                'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
                'latitude', 47.6062,
                'limit', 10,
                'longitude', -122.3321,
                'offset', 0,
                'sort_by', 'distance',
                'sort_direction', 'desc'
            ))::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(
        :'eventNoLocationID',
        :'eventFarID',
        :'eventTie1ID',
        :'eventTie2ID',
        :'eventTie3ID',
        :'eventLaterID'
    ),
    'Should order equal distances by start time then event ID when sorting by descending distance'
);

-- Should order events with equal start times by event ID
select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events(jsonb_build_object(
                'community', jsonb_build_array('ordering-community'),
                'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
                'limit', 10,
                'offset', 0,
                'sort_direction', 'asc'
            ))::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(
        :'eventNoLocationID',
        :'eventFarID',
        :'eventTie1ID',
        :'eventTie2ID',
        :'eventTie3ID',
        :'eventLaterID'
    ),
    'Should order events with equal start times by event ID when sorting by ascending date'
);

select is(
    (
        select jsonb_agg(event_item->>'event_id' order by position)
        from jsonb_array_elements(
            search_events(jsonb_build_object(
                'community', jsonb_build_array('ordering-community'),
                'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
                'limit', 10,
                'offset', 0,
                'sort_direction', 'desc'
            ))::jsonb->'events'
        ) with ordinality as events(event_item, position)
    ),
    jsonb_build_array(
        :'eventLaterID',
        :'eventTie1ID',
        :'eventTie2ID',
        :'eventTie3ID',
        :'eventFarID',
        :'eventNoLocationID'
    ),
    'Should order events with equal start times by event ID when sorting by descending date'
);

-- Should paginate tied events without duplicates or gaps
select is(
    (
        select jsonb_agg(
            search_events(jsonb_build_object(
                'community', jsonb_build_array('ordering-community'),
                'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
                'limit', 1,
                'offset', page_offset
            ))::jsonb->'events'->0->>'event_id'
            order by page_offset
        )
        from generate_series(2, 4) as page_offset
    ),
    jsonb_build_array(:'eventTie1ID', :'eventTie2ID', :'eventTie3ID'),
    'Should paginate tied events without duplicates or gaps'
);

-- Should place events without a distance consistently
select is(
    jsonb_build_array(
        search_events(jsonb_build_object(
            'community', jsonb_build_array('ordering-community'),
            'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
            'latitude', 47.6062,
            'limit', 1,
            'longitude', -122.3321,
            'offset', 5,
            'sort_by', 'distance',
            'sort_direction', 'asc'
        ))::jsonb->'events'->0->>'event_id',
        search_events(jsonb_build_object(
            'community', jsonb_build_array('ordering-community'),
            'group', jsonb_build_array('ordering-located-group', 'ordering-unlocated-group'),
            'latitude', 47.6062,
            'limit', 1,
            'longitude', -122.3321,
            'offset', 0,
            'sort_by', 'distance',
            'sort_direction', 'desc'
        ))::jsonb->'events'->0->>'event_id'
    ),
    jsonb_build_array(:'eventNoLocationID', :'eventNoLocationID'),
    'Should place events without a distance consistently'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
