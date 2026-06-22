-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a090000-0000-0000-0000-000000000001'
\set event1ID '3a090000-0000-0000-0000-000000000002'
\set event2ID '3a090000-0000-0000-0000-000000000003'
\set eventCategoryID '3a090000-0000-0000-0000-000000000004'
\set eventSeriesID '3a090000-0000-0000-0000-000000000005'
\set groupCategoryID '3a090000-0000-0000-0000-000000000006'
\set groupID '3a090000-0000-0000-0000-000000000007'
\set userID '3a090000-0000-0000-0000-000000000008'

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
    1,
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
    starts_at,
    ends_at,

    canceled,
    published
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
        now() + interval '1 day',
        now() + interval '1 day 1 hour',

        false,
        true
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
        now() + interval '8 days',
        now() + interval '8 days 1 hour',

        false,
        true
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel all requested events
select lives_ok(
    format(
        $$
        select cancel_event_series_events(
            %L::uuid,
            %L::uuid,
            array[
                %L::uuid,
                %L::uuid
            ]
        )
        $$,
        :'userID', :'groupID', :'event1ID', :'event2ID'
    ),
    'Should cancel all requested events'
);

-- Should mark all requested events as canceled
select results_eq(
    format(
        $$
        select
            canceled
        from event
        where event_id in (
            %L::uuid,
            %L::uuid
        )
        order by event_id
        $$,
        :'event1ID', :'event2ID'
    ),
    $$
        values (true), (true)
    $$,
    'Should mark all requested events as canceled'
);

-- Should create one audit row per canceled event
select is(
    (select count(*)::int from audit_log where action = 'event_canceled'),
    2,
    'Should create one audit row per canceled event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
