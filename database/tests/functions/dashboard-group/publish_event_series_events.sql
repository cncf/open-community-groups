-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000031'
\set event2ID '00000000-0000-0000-0000-000000000032'
\set eventMixedDraftID '00000000-0000-0000-0000-000000000035'
\set eventNoStartID '00000000-0000-0000-0000-000000000034'
\set eventPublishedID '00000000-0000-0000-0000-000000000036'
\set eventRollbackID '00000000-0000-0000-0000-000000000033'
\set eventSeriesID '00000000-0000-0000-0000-000000000040'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set previousPublisherID '00000000-0000-0000-0000-000000000021'
\set sessionPublishedMeetingID '00000000-0000-0000-0000-000000000051'
\set userID '00000000-0000-0000-0000-000000000020'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
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
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Meetup', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'communityID',
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
        :'categoryID',
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
        :'categoryID',
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
        :'categoryID',
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
        :'categoryID',
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
    :'categoryID',
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
    :'categoryID',
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
    $$
        select publish_event_series_events(
            '00000000-0000-0000-0000-000000000020'::uuid,
            '00000000-0000-0000-0000-000000000002'::uuid,
            array[
                '00000000-0000-0000-0000-000000000031'::uuid,
                '00000000-0000-0000-0000-000000000032'::uuid
            ],
            null
        )
    $$,
    'Should publish all requested events'
);

-- Should mark all requested events as published
select results_eq(
    $$
        select
            published,
            published_at is not null,
            published_by
        from event
        where event_id in (
            '00000000-0000-0000-0000-000000000031'::uuid,
            '00000000-0000-0000-0000-000000000032'::uuid
        )
        order by event_id
    $$,
    $$
        values
            (true, true, '00000000-0000-0000-0000-000000000020'::uuid),
            (true, true, '00000000-0000-0000-0000-000000000020'::uuid)
    $$,
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
    $$
        select publish_event_series_events(
            '00000000-0000-0000-0000-000000000020'::uuid,
            '00000000-0000-0000-0000-000000000002'::uuid,
            array[
                '00000000-0000-0000-0000-000000000035'::uuid,
                '00000000-0000-0000-0000-000000000036'::uuid
            ],
            null
        )
    $$,
    'Should publish drafts without changing already published events'
);

-- Should preserve already published event metadata and meeting sync
select results_eq(
    $$
        select
            e.meeting_in_sync,
            e.published_at,
            e.published_by,
            s.meeting_in_sync
        from event e
        join session s on s.event_id = e.event_id
        where e.event_id = '00000000-0000-0000-0000-000000000036'::uuid
    $$,
    $$
        values (
            true,
            '2025-01-01 10:00:00+00'::timestamptz,
            '00000000-0000-0000-0000-000000000021'::uuid,
            true
        )
    $$,
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
    $$
        select publish_event_series_events(
            '00000000-0000-0000-0000-000000000020'::uuid,
            '00000000-0000-0000-0000-000000000002'::uuid,
            array[
                '00000000-0000-0000-0000-000000000033'::uuid,
                '00000000-0000-0000-0000-000000000034'::uuid
            ],
            null
        )
    $$,
    'P0001',
    'event must have a start date to be published',
    'Should reject invalid batches before keeping partial changes'
);

-- Should leave valid events unchanged when the batch is invalid
select is(
    (
        select published
        from event
        where event_id = '00000000-0000-0000-0000-000000000033'::uuid
    ),
    false,
    'Should leave valid events unchanged when the batch is invalid'
);

select * from finish();
rollback;
