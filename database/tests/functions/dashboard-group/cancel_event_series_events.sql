-- Tests canceling every occurrence of an event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID '3a090000-0000-0000-0000-000000000009'
\set communityID '3a090000-0000-0000-0000-000000000001'
\set event1ID '3a090000-0000-0000-0000-000000000002'
\set event2ID '3a090000-0000-0000-0000-000000000003'
\set eventCategoryID '3a090000-0000-0000-0000-000000000004'
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
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event series linking the occurrences
select fx_event_series(:'eventSeriesID', :'groupID');

-- Upcoming series occurrences canceled together
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

-- Pending co-host rows on every occurrence
insert into event_cohost (event_id, group_id) values
    (:'event1ID', :'cohostGroupID'),
    (:'event2ID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject an empty event selection
select throws_ok(
    format(
        $$select cancel_event_series_events(%L::uuid, %L::uuid, array[]::uuid[])$$,
        :'userID', :'groupID'
    ),
    'OCG01',
    'event_ids cannot be empty',
    'Should reject an empty event selection'
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

-- Should close co-host rows for all requested events
select results_eq(
    format(
        $$
        select event_id, event_cohost_status_id
        from event_cohost
        where event_id in (%L::uuid, %L::uuid)
        order by event_id
        $$,
        :'event1ID', :'event2ID'
    ),
    format(
        $$ values (%L::uuid, 'event-canceled'::text), (%L::uuid, 'event-canceled'::text) $$,
        :'event1ID', :'event2ID'
    ),
    'Should close co-host rows for all requested events'
);

-- Should create one audit row per canceled event
select results_eq(
    $$
        select resource_id, actor_user_id
        from audit_log
        where action = 'event_canceled'
        order by resource_id
    $$,
    format(
        $$ values (%L::uuid, %L::uuid), (%L::uuid, %L::uuid) $$,
        :'event1ID', :'userID', :'event2ID', :'userID'
    ),
    'Should create one audit row per canceled event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
