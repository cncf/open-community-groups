-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '00000000-0000-0000-0000-000000000034'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set deletedEventID '00000000-0000-0000-0000-000000000035'
\set event1ID '00000000-0000-0000-0000-000000000031'
\set event2ID '00000000-0000-0000-0000-000000000032'
\set eventSeriesID '00000000-0000-0000-0000-000000000040'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set standaloneEventID '00000000-0000-0000-0000-000000000033'
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
        :'categoryID',
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
        :'categoryID',
        'virtual',
        '2030-01-14 10:00:00+00',
        '2030-01-14 11:00:00+00',

        false,
        false,
        :'eventSeriesID'
    ),
    (
        :'standaloneEventID',
        :'groupID',
        'Standalone Event',
        'standalone-event',
        'Standalone event',
        'UTC',
        :'categoryID',
        'virtual',
        '2030-01-21 10:00:00+00',
        '2030-01-21 11:00:00+00',

        false,
        false,
        null
    ),
    (
        :'canceledEventID',
        :'groupID',
        'Canceled Series Event',
        'canceled-series-event',
        'Canceled event',
        'UTC',
        :'categoryID',
        'virtual',
        '2030-01-28 10:00:00+00',
        '2030-01-28 11:00:00+00',

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
        :'categoryID',
        'virtual',
        '2030-02-04 10:00:00+00',
        '2030-02-04 11:00:00+00',

        false,
        true,
        :'eventSeriesID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only publishable events from the selected event series
select results_eq(
    $$
        select unnest(
            list_event_series_publishable_event_ids(
                '00000000-0000-0000-0000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000031'::uuid
            )
        )
    $$,
    $$
        values
            ('00000000-0000-0000-0000-000000000031'::uuid),
            ('00000000-0000-0000-0000-000000000032'::uuid)
    $$,
    'Should list only publishable events from the selected event series'
);

-- Should return the selected standalone event when it is publishable
select results_eq(
    $$
        select unnest(
            list_event_series_publishable_event_ids(
                '00000000-0000-0000-0000-000000000002'::uuid,
                '00000000-0000-0000-0000-000000000033'::uuid
            )
        )
    $$,
    $$
        values ('00000000-0000-0000-0000-000000000033'::uuid)
    $$,
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

select * from finish();
rollback;
