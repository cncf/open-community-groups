-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a1d0000-0000-0000-0000-000000000001'
\set communityID '3a1d0000-0000-0000-0000-000000000002'
\set deletedEventID '3a1d0000-0000-0000-0000-000000000003'
\set event1ID '3a1d0000-0000-0000-0000-000000000004'
\set event2ID '3a1d0000-0000-0000-0000-000000000005'
\set event3ID '3a1d0000-0000-0000-0000-000000000006'
\set eventCategoryID '3a1d0000-0000-0000-0000-000000000007'
\set eventSeriesID '3a1d0000-0000-0000-0000-000000000008'
\set groupCategoryID '3a1d0000-0000-0000-0000-000000000009'
\set groupID '3a1d0000-0000-0000-0000-000000000010'
\set standaloneEventID '3a1d0000-0000-0000-0000-000000000011'
\set userID '3a1d0000-0000-0000-0000-000000000012'

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

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Meetup', :'communityID');

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
    event_series_id,
    published
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
        :'eventSeriesID',
        false
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
        :'eventSeriesID',
        true
    ),
    (
        :'event3ID',
        :'groupID',
        'Third Series Event',
        'third-series-event',
        'Third event',
        'UTC',
        :'eventCategoryID',
        'virtual',
        '2030-01-21 10:00:00+00',
        '2030-01-21 11:00:00+00',

        false,
        false,
        :'eventSeriesID',
        false
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
        '2030-01-21 10:00:00+00',
        '2030-01-21 11:00:00+00',

        false,
        false,
        null,
        false
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
        '2030-01-28 10:00:00+00',
        '2030-01-28 11:00:00+00',

        true,
        false,
        :'eventSeriesID',
        false
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
        '2030-02-04 10:00:00+00',
        '2030-02-04 11:00:00+00',

        false,
        true,
        :'eventSeriesID',
        false
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only publishable events from the selected event series
select results_eq(
    format(
        $$
        select unnest(
            list_event_series_publishable_event_ids(
                %L::uuid,
                %L::uuid
            )
        )
        $$,
        :'groupID', :'event1ID'
    ),
    format(
        $$
        values
            (%L::uuid),
            (%L::uuid)
        $$,
        :'event1ID', :'event3ID'
    ),
    'Should list only publishable events from the selected event series'
);

-- Should return an empty array when the selected event is already published
select is(
    cardinality(list_event_series_publishable_event_ids(
        :'groupID'::uuid,
        :'event2ID'::uuid
    )),
    0,
    'Should return an empty array when the selected event is already published'
);

-- Should return the selected standalone event when it is publishable
select results_eq(
    format(
        $$
        select unnest(
            list_event_series_publishable_event_ids(
                %L::uuid,
                %L::uuid
            )
        )
        $$,
        :'groupID', :'standaloneEventID'
    ),
    format(
        $$ values (%L::uuid) $$,
        :'standaloneEventID'
    ),
    'Should return the selected standalone event when it is publishable'
);

-- Should return an empty array when the selected event is canceled
select is(
    cardinality(list_event_series_publishable_event_ids(
        :'groupID'::uuid,
        :'canceledEventID'::uuid
    )),
    0,
    'Should return an empty array when the selected event is canceled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
