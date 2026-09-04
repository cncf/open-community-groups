-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a1d0000-0000-0000-0000-000000000001'
\set communityID '3a1d0000-0000-0000-0000-000000000002'
\set deletedEventID '3a1d0000-0000-0000-0000-000000000003'
\set event1ID '3a1d0000-0000-0000-0000-000000000004'
\set event2ID '3a1d0000-0000-0000-0000-000000000005'
\set event3ID '3a1d0000-0000-0000-0000-000000000006'
\set eventCategoryID '3a1d0000-0000-0000-0000-000000000007'
\set eventSeriesID '3a1d0000-0000-0000-0000-000000000008'
\set groupCategoryID '3a1d0000-0000-0000-0000-000000000009'
\set groupID '3a1d0000-0000-0000-0000-000000000010'
\set standaloneEventID '3a1d0000-0000-0000-0000-000000000011'
\set userID '3a1d0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event Series
insert into event_series (
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone,

    created_by
) values (
    :'eventSeriesID',
    :'groupID',
    3,
    '2030-01-07 10:00:00+00',
    'weekly',
    'UTC',

    :'userID'
);

-- Events
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
    'published', true,
    'starts_at', '2030-01-14 10:00:00+00'
));
select fx_event(:'event3ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-21 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-21 10:00:00+00'
));
select fx_event(:'standaloneEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-21 11:00:00+00',
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-21 10:00:00+00'
));
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', '2030-01-28 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-28 10:00:00+00'
));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'ends_at', '2030-02-04 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-02-04 10:00:00+00'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only publishable events from the selected event series
select results_eq(
    format(
        $$
        select unnest(
            list_event_series_publishable_event_ids(
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
        :'event1ID', :'event3ID'
    ),
    'Should list only publishable events from the selected event series'
);

-- Should return an empty array when the selected event is already published
select is(
    cardinality(list_event_series_publishable_event_ids(
        :'groupID'::uuid,
        :'event2ID'::uuid
    )),
    0,
    'Should return an empty array when the selected event is already published'
);

-- Should return the selected standalone event when it is publishable
select results_eq(
    format(
        $$
        select unnest(
            list_event_series_publishable_event_ids(
                %L::uuid,
                %L::uuid
            )
        )
        $$,
        :'groupID', :'standaloneEventID'
    ),
    format(
        $$ values (%L::uuid) $$,
        :'standaloneEventID'
    ),
    'Should return the selected standalone event when it is publishable'
);

-- Should return an empty array when the selected event is canceled
select is(
    cardinality(list_event_series_publishable_event_ids(
        :'groupID'::uuid,
        :'canceledEventID'::uuid
    )),
    0,
    'Should return an empty array when the selected event is canceled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
