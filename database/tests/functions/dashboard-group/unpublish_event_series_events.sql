-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a370000-0000-0000-0000-000000000001'
\set event1ID '3a370000-0000-0000-0000-000000000002'
\set event2ID '3a370000-0000-0000-0000-000000000003'
\set eventCategoryID '3a370000-0000-0000-0000-000000000004'
\set eventSeriesID '3a370000-0000-0000-0000-000000000005'
\set groupCategoryID '3a370000-0000-0000-0000-000000000006'
\set groupID '3a370000-0000-0000-0000-000000000007'
\set userID '3a370000-0000-0000-0000-000000000008'

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
    'published_at', now(),
    'published_by', :'userID',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '8 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'published_at', now(),
    'published_by', :'userID',
    'starts_at', now() + interval '8 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should unpublish all requested events
select lives_ok(
    format(
        $$
        select unpublish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[%L::uuid, %L::uuid]
        )
        $$,
        :'userID', :'groupID', :'event1ID', :'event2ID'
    ),
    'Should unpublish all requested events'
);

-- Should clear publication metadata for all requested events
select results_eq(
    format(
        $$
        select
            published,
            published_at is null,
            published_by is null
        from event
        where event_id in (%L::uuid, %L::uuid)
        order by event_id
        $$,
        :'event1ID', :'event2ID'
    ),
    $$
        values (false, true, true), (false, true, true)
    $$,
    'Should clear publication metadata for all requested events'
);

-- Should create one audit row per unpublished event
select is(
    (select count(*)::int from audit_log where action = 'event_unpublished'),
    2,
    'Should create one audit row per unpublished event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
