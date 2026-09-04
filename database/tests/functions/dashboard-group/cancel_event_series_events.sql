-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a090000-0000-0000-0000-000000000001'
\set event1ID '3a090000-0000-0000-0000-000000000002'
\set event2ID '3a090000-0000-0000-0000-000000000003'
\set eventCanceledID '3a090000-0000-0000-0000-000000000009'
\set eventCategoryID '3a090000-0000-0000-0000-000000000004'
\set eventPastID '3a090000-0000-0000-0000-000000000010'
\set eventSeriesID '3a090000-0000-0000-0000-000000000005'
\set groupCategoryID '3a090000-0000-0000-0000-000000000006'
\set groupID '3a090000-0000-0000-0000-000000000007'
\set userID '3a090000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and groups
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
    1,
    now() + interval '1 day',
    'weekly',
    'UTC',

    :'userID'
);

-- Events
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '8 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'starts_at', now() + interval '8 days'
));
select fx_event(:'eventPastID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'starts_at', now() - interval '2 hours'
));
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '15 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'starts_at', now() + interval '15 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only non-completed, non-canceled series occurrences
select is(
    list_event_series_cancelable_event_ids(:'groupID', :'eventPastID'),
    array[:'event1ID'::uuid, :'event2ID'::uuid],
    'Should list only non-completed, non-canceled series occurrences'
);

-- Should cancel all requested events
select lives_ok(
    format(
        $$
        select cancel_event_series_events(
            %L::uuid,
            %L::uuid,
            array[
                %L::uuid,
                %L::uuid
            ]
        )
        $$,
        :'userID', :'groupID', :'event1ID', :'event2ID'
    ),
    'Should cancel all requested events'
);

-- Should mark all requested events as canceled
select results_eq(
    format(
        $$
        select
            canceled
        from event
        where event_id in (
            %L::uuid,
            %L::uuid
        )
        order by event_id
        $$,
        :'event1ID', :'event2ID'
    ),
    $$
        values (true), (true)
    $$,
    'Should mark all requested events as canceled'
);

-- Should create one audit row per canceled event
select is(
    (select count(*)::int from audit_log where action = 'event_canceled'),
    2,
    'Should create one audit row per canceled event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
