-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a1c0000-0000-0000-0000-000000000001'
\set deletedEventID '3a1c0000-0000-0000-0000-000000000002'
\set event1ID '3a1c0000-0000-0000-0000-000000000003'
\set event2ID '3a1c0000-0000-0000-0000-000000000004'
\set eventCategoryID '3a1c0000-0000-0000-0000-000000000005'
\set eventSeriesID '3a1c0000-0000-0000-0000-000000000006'
\set groupCategoryID '3a1c0000-0000-0000-0000-000000000007'
\set groupID '3a1c0000-0000-0000-0000-000000000008'
\set standaloneEventID '3a1c0000-0000-0000-0000-000000000009'
\set userID '3a1c0000-0000-0000-0000-000000000010'

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
    2,
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
        :'eventSeriesID'
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
        null
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

        true,
        :'eventSeriesID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active events from the selected event series
select results_eq(
    format(
        $$
        select unnest(
            list_event_series_event_ids(
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
        :'event1ID', :'event2ID'
    ),
    'Should list active events from the selected event series'
);

-- Should return an empty array when the event is not part of a series
select is(
    cardinality(list_event_series_event_ids(
        :'groupID'::uuid,
        :'standaloneEventID'::uuid
    )),
    0,
    'Should return an empty array when the event is not part of a series'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
