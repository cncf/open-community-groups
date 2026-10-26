-- Tests publishing the events of an event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostPendingGroupID '3a0b0000-0000-0000-0000-000000000015'
\set communityID '3a0b0000-0000-0000-0000-000000000001'
\set event1ID '3a0b0000-0000-0000-0000-000000000002'
\set event2ID '3a0b0000-0000-0000-0000-000000000003'
\set eventCanceledID '3a0b0000-0000-0000-0000-000000000018'
\set eventCategoryID '3a0b0000-0000-0000-0000-000000000004'
\set eventCohostPendingID '3a0b0000-0000-0000-0000-000000000016'
\set eventCohostReadyID '3a0b0000-0000-0000-0000-000000000017'
\set eventMixedDraftID '3a0b0000-0000-0000-0000-000000000005'
\set eventNoStartID '3a0b0000-0000-0000-0000-000000000006'
\set eventPublishedID '3a0b0000-0000-0000-0000-000000000007'
\set eventRollbackID '3a0b0000-0000-0000-0000-000000000008'
\set eventSeriesID '3a0b0000-0000-0000-0000-000000000009'
\set groupCategoryID '3a0b0000-0000-0000-0000-000000000010'
\set groupID '3a0b0000-0000-0000-0000-000000000011'
\set userID '3a0b0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Co-host group that has not answered its invitation
select fx_group(:'cohostPendingGroupID', :'communityID', :'groupCategoryID');

-- User
select fx_user(:'userID', jsonb_build_object('auth_hash', 'hash'));

-- Event series linking the occurrences
select fx_event_series(:'eventSeriesID', :'groupID');

-- Events
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '8 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '8 days'
));
select fx_event(:'eventRollbackID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '15 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '15 days'
));
select fx_event(:'eventNoStartID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID'
));

-- Mixed draft event
select fx_event(:'eventMixedDraftID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '22 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '22 days'
));

-- Already published event
select fx_event(:'eventPublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '29 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'published', true,
    'starts_at', now() + interval '29 days'
));

-- Series draft with an unanswered co-host invitation
select fx_event(:'eventCohostPendingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '36 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '36 days'
));

-- Series draft ready to publish next to the blocked occurrence
select fx_event(:'eventCohostReadyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '43 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '43 days'
));

-- Canceled series draft rejected by the series event validation
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '50 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'starts_at', now() + interval '50 days'
));

-- Pending co-host invitation that blocks the whole series
insert into event_cohost (event_cohost_status_id, event_id, group_id)
values ('pending', :'eventCohostPendingID', :'cohostPendingGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should publish all requested events
select lives_ok(
    format(
        $$
        select publish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[%L::uuid, %L::uuid],
            null
        )
        $$,
        :'userID', :'groupID', :'event1ID', :'event2ID'
    ),
    'Should publish all requested events'
);

-- Should mark all requested events as published
select results_eq(
    format(
        $$
        select
            published,
            published_at = current_timestamp,
            published_by
        from event
        where event_id in (%L::uuid, %L::uuid)
        order by event_id
        $$,
        :'event1ID', :'event2ID'
    ),
    format(
        $$
        values
            (true, true, %L::uuid),
            (true, true, %L::uuid)
        $$,
        :'userID', :'userID'
    ),
    'Should mark all requested events as published'
);

-- Should create one audit row per published event
select is(
    (select count(*)::int from audit_log where action = 'event_published'),
    2,
    'Should create one audit row per published event'
);

-- Should publish drafts without changing already published events
select lives_ok(
    format(
        $$
        select publish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[%L::uuid, %L::uuid],
            null
        )
        $$,
        :'userID', :'groupID', :'eventMixedDraftID', :'eventPublishedID'
    ),
    'Should publish drafts without changing already published events'
);

-- Should mark the mixed draft event as published
select is(
    (select published from event where event_id = :'eventMixedDraftID'),
    true,
    'Should mark the mixed draft event as published'
);

-- Should create audit rows only for newly published events
select is(
    (select count(*)::int from audit_log where action = 'event_published'),
    3,
    'Should create audit rows only for newly published events'
);

-- Should reject the batch when one event has no start date
select throws_ok(
    format(
        $$
        select publish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[%L::uuid, %L::uuid],
            null
        )
        $$,
        :'userID', :'groupID', :'eventRollbackID', :'eventNoStartID'
    ),
    'OCG01',
    'event must have a start date to be published',
    'Should reject the batch when one event has no start date'
);

-- Should reject the series while one occurrence has a pending co-host
select throws_ok(
    format(
        $$
        select publish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[%L::uuid, %L::uuid],
            null
        )
        $$,
        :'userID', :'groupID', :'eventCohostPendingID', :'eventCohostReadyID'
    ),
    'OCG01',
    'co-hosts must respond for every event in the series before publishing',
    'Should reject the series while one occurrence has a pending co-host'
);

-- Should reject canceled events through the series event validation
select throws_ok(
    format(
        $$
        select publish_event_series_events(
            %L::uuid,
            %L::uuid,
            array[%L::uuid],
            null
        )
        $$,
        :'userID', :'groupID', :'eventCanceledID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject canceled events through the series event validation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
