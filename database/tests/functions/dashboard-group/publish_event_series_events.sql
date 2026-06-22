-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a2c0000-0000-0000-0000-000000000001'
\set event1ID '3a2c0000-0000-0000-0000-000000000002'
\set event2ID '3a2c0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2c0000-0000-0000-0000-000000000004'
\set eventMixedDraftID '3a2c0000-0000-0000-0000-000000000005'
\set eventNoStartID '3a2c0000-0000-0000-0000-000000000006'
\set eventPublishedID '3a2c0000-0000-0000-0000-000000000007'
\set eventRollbackID '3a2c0000-0000-0000-0000-000000000008'
\set eventSeriesID '3a2c0000-0000-0000-0000-000000000009'
\set groupCategoryID '3a2c0000-0000-0000-0000-000000000010'
\set groupID '3a2c0000-0000-0000-0000-000000000011'
\set previousPublisherID '3a2c0000-0000-0000-0000-000000000012'
\set sessionPublishedMeetingID '3a2c0000-0000-0000-0000-000000000013'
\set userID '3a2c0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- User
insert into "user" (user_id, email, username, auth_hash)
values (:'userID', 'organizer@example.com', 'organizer', 'hash');

-- User (previous publisher)
insert into "user" (user_id, email, username, auth_hash)
values (:'previousPublisherID', 'publisher@example.com', 'publisher', 'hash');

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'Meetup', :'allianceID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategoryID', 'Technology', :'allianceID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'allianceID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

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
insert into event (
    event_id,
    event_series_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,

    ends_at,
    published,
    starts_at
) values
    (
        :'event1ID',
        :'eventSeriesID',
        :'groupID',
        'First Series Event',
        'first-series-event',
        'First event',
        'UTC',
        :'eventCategoryID',
        'virtual',

        now() + interval '1 day 1 hour',
        false,
        now() + interval '1 day'
    ),
    (
        :'event2ID',
        :'eventSeriesID',
        :'groupID',
        'Second Series Event',
        'second-series-event',
        'Second event',
        'UTC',
        :'eventCategoryID',
        'virtual',

        now() + interval '8 days 1 hour',
        false,
        now() + interval '8 days'
    ),
    (
        :'eventRollbackID',
        :'eventSeriesID',
        :'groupID',
        'Rollback Series Event',
        'rollback-series-event',
        'Rollback event',
        'UTC',
        :'eventCategoryID',
        'virtual',

        now() + interval '15 days 1 hour',
        false,
        now() + interval '15 days'
    ),
    (
        :'eventNoStartID',
        :'eventSeriesID',
        :'groupID',
        'No Start Event',
        'no-start-event',
        'Invalid event',
        'UTC',
        :'eventCategoryID',
        'virtual',

        null,
        false,
        null
    );

-- Mixed draft event
insert into event (
    event_id,
    event_series_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,

    ends_at,
    published,
    starts_at
) values (
    :'eventMixedDraftID',
    :'eventSeriesID',
    :'groupID',
    'Mixed Draft Event',
    'mixed-draft-event',
    'Draft event',
    'UTC',
    :'eventCategoryID',
    'virtual',

    now() + interval '22 days 1 hour',
    false,
    now() + interval '22 days'
);

-- Already published event
insert into event (
    event_id,
    event_series_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published,
    published_at,
    published_by,
    starts_at
) values (
    :'eventPublishedID',
    :'eventSeriesID',
    :'groupID',
    'Already Published Event',
    'already-published-event',
    'Published event',
    'UTC',
    :'eventCategoryID',
    'virtual',

    100,
    now() + interval '29 days 1 hour',
    true,
    'zoom',
    true,
    true,
    '2025-01-01 10:00:00+00',
    :'previousPublisherID',
    now() + interval '29 days'
);

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
    'P0001',
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
