-- Tests unpublishing the events of an event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID '3a370000-0000-0000-0000-000000000009'
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
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event series linking the occurrences
select fx_event_series(:'eventSeriesID', :'groupID');

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

-- Approved co-host rows on every occurrence
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'event1ID', :'cohostGroupID'),
    ('2025-01-02 00:00:00+00', 'approved', :'event2ID', :'cohostGroupID');

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

-- Should preserve co-host status and approval evidence for all requested events
select results_eq(
    format(
        $$
        select event_id, event_cohost_status_id, approved_at
        from event_cohost
        where event_id in (%L::uuid, %L::uuid)
        order by event_id
        $$,
        :'event1ID', :'event2ID'
    ),
    format(
        $$
            values
                (%L::uuid, 'approved'::text, '2025-01-01 00:00:00+00'::timestamptz),
                (%L::uuid, 'approved'::text, '2025-01-02 00:00:00+00'::timestamptz)
        $$,
        :'event1ID', :'event2ID'
    ),
    'Should preserve co-host status and approval evidence for all requested events'
);

-- Should create one audit row per unpublished event
select is(
    (select count(*)::int from audit_log where action = 'event_unpublished'),
    2,
    'Should create one audit row per unpublished event'
);

-- Should reject an empty event list through the series event validation
select throws_ok(
    format(
        $$
        select unpublish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[]::uuid[]
        )
        $$,
        :'userID', :'groupID'
    ),
    'OCG01',
    'event_ids cannot be empty',
    'Should reject an empty event list through the series event validation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
