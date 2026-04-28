-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000031'
\set event2ID '00000000-0000-0000-0000-000000000032'
\set eventSeriesID '00000000-0000-0000-0000-000000000040'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
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
        :'categoryID',
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
        :'categoryID',
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
    $$
        select cancel_event_series_events(
            '00000000-0000-0000-0000-000000000020'::uuid,
            '00000000-0000-0000-0000-000000000002'::uuid,
            array[
                '00000000-0000-0000-0000-000000000031'::uuid,
                '00000000-0000-0000-0000-000000000032'::uuid
            ]
        )
    $$,
    'Should cancel all requested events'
);

-- Should mark all requested events as canceled
select results_eq(
    $$
        select
            canceled
        from event
        where event_id in (
            '00000000-0000-0000-0000-000000000031'::uuid,
            '00000000-0000-0000-0000-000000000032'::uuid
        )
        order by event_id
    $$,
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

select * from finish();
rollback;
