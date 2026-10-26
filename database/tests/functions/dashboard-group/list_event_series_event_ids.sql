-- Tests listing the active events of the selected event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a1c0000-0000-0000-0000-000000000001'
\set deletedEventID '3a1c0000-0000-0000-0000-000000000002'
\set event1ID '3a1c0000-0000-0000-0000-000000000003'
\set event2ID '3a1c0000-0000-0000-0000-000000000004'
\set eventCategoryID '3a1c0000-0000-0000-0000-000000000005'
\set eventSeriesID '3a1c0000-0000-0000-0000-000000000006'
\set groupCategoryID '3a1c0000-0000-0000-0000-000000000007'
\set groupID '3a1c0000-0000-0000-0000-000000000008'
\set missingEventID '3a1c0000-0000-0000-0000-000000000011'
\set otherEventID '3a1c0000-0000-0000-0000-000000000012'
\set otherGroupID '3a1c0000-0000-0000-0000-000000000013'
\set standaloneEventID '3a1c0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event series of the group
select fx_event_series(:'eventSeriesID', :'groupID');

-- Events of the group series, a standalone event and a deleted occurrence
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-07 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-07 10:00:00+00'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-14 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-14 10:00:00+00'
));
select fx_event(:'standaloneEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-21 11:00:00+00',
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-21 10:00:00+00'
));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'ends_at', '2030-01-28 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-28 10:00:00+00'
));

-- Event of another group linked to the group series
select fx_event(:'otherEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-07 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-07 10:00:00+00'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active events from the selected event series
select results_eq(
    format(
        $$
        select unnest(
            list_event_series_event_ids(
                %L::uuid,
                %L::uuid
            )
        )
        $$,
        :'groupID', :'event1ID'
    ),
    format(
        $$
        values
            (%L::uuid),
            (%L::uuid)
        $$,
        :'event1ID', :'event2ID'
    ),
    'Should list active events from the selected event series'
);

-- Should return an empty array when the event is not part of a series
select is(
    cardinality(list_event_series_event_ids(
        :'groupID'::uuid,
        :'standaloneEventID'::uuid
    )),
    0,
    'Should return an empty array when the event is not part of a series'
);

-- Should return an empty array for a deleted selected event
select is(
    list_event_series_event_ids(:'groupID'::uuid, :'deletedEventID'::uuid),
    '{}'::uuid[],
    'Should return an empty array for a deleted selected event'
);

-- Should return an empty array for a missing event
select is(
    list_event_series_event_ids(:'groupID'::uuid, :'missingEventID'::uuid),
    '{}'::uuid[],
    'Should return an empty array for a missing event'
);

-- Should return an empty array when the selected event belongs to another group
select is(
    list_event_series_event_ids(:'groupID'::uuid, :'otherEventID'::uuid),
    '{}'::uuid[],
    'Should return an empty array when the selected event belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
