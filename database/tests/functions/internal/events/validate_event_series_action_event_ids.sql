-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a450000-0000-0000-0000-000000000001'
\set communityID '3a450000-0000-0000-0000-000000000002'
\set deletedEventID '3a450000-0000-0000-0000-000000000003'
\set event1ID '3a450000-0000-0000-0000-000000000004'
\set event2ID '3a450000-0000-0000-0000-000000000005'
\set eventCategoryID '3a450000-0000-0000-0000-000000000006'
\set eventSeriesID '3a450000-0000-0000-0000-000000000007'
\set groupCategoryID '3a450000-0000-0000-0000-000000000008'
\set groupID '3a450000-0000-0000-0000-000000000009'
\set otherEventID '3a450000-0000-0000-0000-000000000010'
\set otherEventSeriesID '3a450000-0000-0000-0000-000000000011'
\set standaloneEventID '3a450000-0000-0000-0000-000000000012'
\set userID '3a450000-0000-0000-0000-000000000013'

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
) values
    (
        :'eventSeriesID',
        :'groupID',
        3,
        '2030-01-07 10:00:00+00',
        'weekly',
        'UTC',

        :'userID'
    ),
    (
        :'otherEventSeriesID',
        :'groupID',
        1,
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
    'starts_at', '2030-01-14 10:00:00+00'
));
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', '2030-01-21 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-21 10:00:00+00'
));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'ends_at', '2030-01-28 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', '2030-01-28 10:00:00+00'
));
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-02-04 11:00:00+00',
    'event_kind_id', 'virtual',
    'event_series_id', :'otherEventSeriesID',
    'starts_at', '2030-02-04 10:00:00+00'
));
select fx_event(:'standaloneEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-02-11 11:00:00+00',
    'event_kind_id', 'virtual',
    'starts_at', '2030-02-11 10:00:00+00'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should normalize and sort event ids from the same series
select results_eq(
    format(
        $$
        select unnest(validate_event_series_action_event_ids(
            %L::uuid,
            array[
                %L::uuid,
                %L::uuid,
                %L::uuid
            ]
        ))
        $$,
        :'groupID',
        :'event2ID',
        :'event1ID',
        :'event1ID'
    ),
    format(
        $$
        values
            (%L::uuid),
            (%L::uuid)
        $$,
        :'event1ID',
        :'event2ID'
    ),
    'Should normalize and sort event ids from the same series'
);

-- Should allow canceled events when not required for publishing
select results_eq(
    format(
        $$
        select unnest(validate_event_series_action_event_ids(
            %L::uuid,
            array[%L::uuid],
            false
        ))
        $$,
        :'groupID',
        :'canceledEventID'
    ),
    format($$ values (%L::uuid) $$, :'canceledEventID'),
    'Should allow canceled events when not required for publishing'
);

-- Should reject empty event ids
select throws_ok(
    format(
        $$
        select validate_event_series_action_event_ids(
            %L::uuid,
            '{}'::uuid[]
        )
        $$,
        :'groupID'
    ),
    'OCG01',
    'event_ids cannot be empty',
    'Should reject empty event ids'
);

-- Should reject inactive event ids
select throws_ok(
    format(
        $$
        select validate_event_series_action_event_ids(
            %L::uuid,
            array[%L::uuid]
        )
        $$,
        :'groupID',
        :'deletedEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject inactive event ids'
);

-- Should reject canceled event ids when publishing
select throws_ok(
    format(
        $$
        select validate_event_series_action_event_ids(
            %L::uuid,
            array[%L::uuid],
            true
        )
        $$,
        :'groupID',
        :'canceledEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject canceled event ids when publishing'
);

-- Should reject events from different series
select throws_ok(
    format(
        $$
        select validate_event_series_action_event_ids(
            %L::uuid,
            array[
                %L::uuid,
                %L::uuid
            ]
        )
        $$,
        :'groupID',
        :'event1ID',
        :'otherEventID'
    ),
    'OCG01',
    'events must belong to the same series',
    'Should reject events from different series'
);

-- Should reject standalone events
select throws_ok(
    format(
        $$
        select validate_event_series_action_event_ids(
            %L::uuid,
            array[%L::uuid]
        )
        $$,
        :'groupID',
        :'standaloneEventID'
    ),
    'OCG01',
    'events must belong to the same series',
    'Should reject standalone events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
