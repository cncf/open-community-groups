-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a450000-0000-0000-0000-000000000001'
\set allianceID '3a450000-0000-0000-0000-000000000002'
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

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

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
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    canceled,
    deleted,
    event_series_id
) values
    (
        :'event1ID',
        :'groupID',
        'First Series Event',
        'first-series-event',
        'First event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-01-07 10:00:00+00',
        '2030-01-07 11:00:00+00',

        false,
        false,
        :'eventSeriesID'
    ),
    (
        :'event2ID',
        :'groupID',
        'Second Series Event',
        'second-series-event',
        'Second event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-01-14 10:00:00+00',
        '2030-01-14 11:00:00+00',

        false,
        false,
        :'eventSeriesID'
    ),
    (
        :'canceledEventID',
        :'groupID',
        'Canceled Series Event',
        'canceled-series-event',
        'Canceled event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-01-21 10:00:00+00',
        '2030-01-21 11:00:00+00',

        true,
        false,
        :'eventSeriesID'
    ),
    (
        :'deletedEventID',
        :'groupID',
        'Deleted Series Event',
        'deleted-series-event',
        'Deleted event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-01-28 10:00:00+00',
        '2030-01-28 11:00:00+00',

        false,
        true,
        :'eventSeriesID'
    ),
    (
        :'otherEventID',
        :'groupID',
        'Other Series Event',
        'other-series-event',
        'Other event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-02-04 10:00:00+00',
        '2030-02-04 11:00:00+00',

        false,
        false,
        :'otherEventSeriesID'
    ),
    (
        :'standaloneEventID',
        :'groupID',
        'Standalone Event',
        'standalone-event',
        'Standalone event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-02-11 10:00:00+00',
        '2030-02-11 11:00:00+00',

        false,
        false,
        null
    );

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
    'P0001',
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
    'P0001',
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
    'P0001',
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
    'P0001',
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
    'P0001',
    'events must belong to the same series',
    'Should reject standalone events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
