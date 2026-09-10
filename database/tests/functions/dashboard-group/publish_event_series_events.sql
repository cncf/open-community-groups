-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0b0000-0000-0000-0000-000000000001'
\set event1ID '3a0b0000-0000-0000-0000-000000000002'
\set event2ID '3a0b0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a0b0000-0000-0000-0000-000000000004'
\set eventMixedDraftID '3a0b0000-0000-0000-0000-000000000005'
\set eventNoStartID '3a0b0000-0000-0000-0000-000000000006'
\set eventPublishedID '3a0b0000-0000-0000-0000-000000000007'
\set eventRollbackID '3a0b0000-0000-0000-0000-000000000008'
\set eventSeriesID '3a0b0000-0000-0000-0000-000000000009'
\set groupCategoryID '3a0b0000-0000-0000-0000-000000000010'
\set groupID '3a0b0000-0000-0000-0000-000000000011'
\set previousPublisherID '3a0b0000-0000-0000-0000-000000000012'
\set sessionPublishedMeetingID '3a0b0000-0000-0000-0000-000000000013'
\set userID '3a0b0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- User
select fx_user(:'userID', jsonb_build_object('auth_hash', 'hash'));

-- User (previous publisher)
select fx_user(:'previousPublisherID', jsonb_build_object(
    'auth_hash', 'hash',
    'username', 'publisher'
));

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
    'capacity', 100,
    'ends_at', now() + interval '29 days 1 hour',
    'event_kind_id', 'virtual',
    'event_series_id', :'eventSeriesID',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'published_at', '2025-01-01 10:00:00+00',
    'published_by', :'previousPublisherID',
    'starts_at', now() + interval '29 days'
));

-- Session for the already published event
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionPublishedMeetingID',
    :'eventPublishedID',
    'Already Published Session',
    now() + interval '29 days',
    now() + interval '29 days 30 minutes',
    'virtual',
    true,
    'zoom',
    true
);

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
            published_at is not null,
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

-- Should preserve already published event metadata and meeting sync
select results_eq(
    format(
        $$
        select
            e.meeting_in_sync,
            e.published_at,
            e.published_by,
            s.meeting_in_sync
        from event e
        join session s on s.event_id = e.event_id
        where e.event_id = %L::uuid
        $$,
        :'eventPublishedID'
    ),
    format(
        $$
        values (
            true,
            '2025-01-01 10:00:00+00'::timestamptz,
            %L::uuid,
            true
        )
        $$,
        :'previousPublisherID'
    ),
    'Should preserve already published event metadata and meeting sync'
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

-- Should reject invalid batches before keeping partial changes
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
    'Should reject invalid batches before keeping partial changes'
);

-- Should leave valid events unchanged when the batch is invalid
select is(
    (
        select published
        from event
        where event_id = :'eventRollbackID'::uuid
    ),
    false,
    'Should leave valid events unchanged when the batch is invalid'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
