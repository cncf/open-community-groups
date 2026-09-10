-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '2c0d0000-0000-0000-0000-000000000001'
\set communityID '2c0d0000-0000-0000-0000-000000000002'
\set event1ID '2c0d0000-0000-0000-0000-000000000003'
\set event2ID '2c0d0000-0000-0000-0000-000000000004'
\set event3ID '2c0d0000-0000-0000-0000-000000000005'
\set event4ID '2c0d0000-0000-0000-0000-000000000006'
\set event5ID '2c0d0000-0000-0000-0000-000000000007'
\set event6ID '2c0d0000-0000-0000-0000-000000000008'
\set event7ID '2c0d0000-0000-0000-0000-000000000009'
\set event8ID '2c0d0000-0000-0000-0000-000000000010'
\set eventCategory1ID '2c0d0000-0000-0000-0000-000000000011'
\set eventCategory2ID '2c0d0000-0000-0000-0000-000000000012'
\set group1ID '2c0d0000-0000-0000-0000-000000000013'
\set group2ID '2c0d0000-0000-0000-0000-000000000014'
\set group3ID '2c0d0000-0000-0000-0000-000000000015'
\set group4ID '2c0d0000-0000-0000-0000-000000000016'
\set group5ID '2c0d0000-0000-0000-0000-000000000017'
\set groupCategory1ID '2c0d0000-0000-0000-0000-000000000018'
\set groupCategory2ID '2c0d0000-0000-0000-0000-000000000019'
\set groupCategory3ID '2c0d0000-0000-0000-0000-000000000020'
\set region1ID '2c0d0000-0000-0000-0000-000000000021'
\set region2ID '2c0d0000-0000-0000-0000-000000000022'
\set region3ID '2c0d0000-0000-0000-0000-000000000023'
\set unknownCommunityID '2c0d0000-0000-0000-0000-000000000024'
\set user1ID '2c0d0000-0000-0000-0000-000000000025'
\set user2ID '2c0d0000-0000-0000-0000-000000000026'
\set user3ID '2c0d0000-0000-0000-0000-000000000027'
\set user4ID '2c0d0000-0000-0000-0000-000000000028'
\set user5ID '2c0d0000-0000-0000-0000-000000000029'
\set user6ID '2c0d0000-0000-0000-0000-000000000030'
\set user7ID '2c0d0000-0000-0000-0000-000000000031'
\set user8ID '2c0d0000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and group category
select fx_community(:'community2ID');
select fx_community(:'communityID');
select fx_group_category(:'groupCategory3ID', :'community2ID');

select fx_group_category(:'groupCategory1ID', :'communityID', jsonb_build_object('name', 'AI/ML'));
-- group category
select fx_group_category(:'groupCategory2ID', :'communityID', jsonb_build_object('name', 'Cloud Native'));

-- Event categories
select fx_event_category(:'eventCategory1ID', :'communityID', jsonb_build_object('name', 'Conference'));
-- event category
select fx_event_category(:'eventCategory2ID', :'communityID', jsonb_build_object('name', 'Meetup'));

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-community-stats'));
-- user
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-community-stats'));
-- user
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-community-stats'));
-- user
select fx_user(:'user4ID', jsonb_build_object('username', 'user4-community-stats'));
-- user
select fx_user(:'user5ID', jsonb_build_object('username', 'user5-community-stats'));
-- user
select fx_user(:'user6ID', jsonb_build_object('username', 'user6-community-stats'));
-- user
select fx_user(:'user7ID', jsonb_build_object('username', 'user7'));
-- user
select fx_user(:'user8ID', jsonb_build_object('username', 'user8'));

-- Regions
insert into region (region_id, community_id, name, "order") values
    (:'region1ID', :'communityID', 'Europe', 1),
    (:'region2ID', :'communityID', 'North America', 2),
    (:'region3ID', :'community2ID', 'South America', 1);

-- month_3  = date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months'  (group5, other community)
select fx_group(:'group1ID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months'
        + interval '15 days',
    'region_id', :'region1ID'
));
-- group
select fx_group(:'group2ID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months'
        + interval '15 days',
    'region_id', :'region2ID'
));
-- group
select fx_group(:'group3ID', :'communityID', :'groupCategory2ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months'
        + interval '15 days',
    'region_id', :'region1ID'
));
-- group
select fx_group(:'group4ID', :'communityID', :'groupCategory2ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months'
        + interval '15 days',
    'region_id', :'region2ID'
));
-- group
select fx_group(:'group5ID', :'community2ID', :'groupCategory3ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months'
        + interval '15 days',
    'region_id', :'region3ID'
));

-- Group members
-- Members join across different months:
-- month_11: user1 joins group1 (AI/ML, Europe)
-- month_10: user2 joins group1 (AI/ML, Europe)
-- month_9:  user4 joins group2 (AI/ML, North America)
-- month_8:  user5 joins group2 (AI/ML, North America)
-- month_7:  user6 joins group3 (Cloud Native, Europe)
-- month_6:  user3 joins group1 (AI/ML, Europe)
-- month_5:  user8 joins group4 (Cloud Native, North America)
-- month_4:  user7 joins group3 (Cloud Native, Europe)
insert into group_member (group_id, user_id, created_at) values
    (
        :'group1ID',
        :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '11 months'
            + interval '20 days'
    ),
    (
        :'group1ID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months'
            + interval '10 days'
    ),
    (
        :'group2ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months'
            + interval '20 days'
    ),
    (
        :'group2ID',
        :'user5ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months'
            + interval '10 days'
    ),
    (
        :'group3ID',
        :'user6ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months'
            + interval '20 days'
    ),
    (
        :'group1ID',
        :'user3ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months'
            + interval '5 days'
    ),
    (
        :'group4ID',
        :'user8ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months'
            + interval '20 days'
    ),
    (
        :'group3ID',
        :'user7ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months'
            + interval '10 days'
    );

-- month_0:  event8 (canceled, but its page views should still count)
select fx_event(:'event1ID', :'group1ID', :'eventCategory1ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months'
        + interval '15 days'
));
-- event
select fx_event(:'event2ID', :'group1ID', :'eventCategory2ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months'
        + interval '15 days'
));
-- event
select fx_event(:'event3ID', :'group2ID', :'eventCategory1ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months'
        + interval '15 days'
));
-- event
select fx_event(:'event4ID', :'group3ID', :'eventCategory2ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months'
        + interval '15 days'
));
-- event
select fx_event(:'event5ID', :'group3ID', :'eventCategory1ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months'
        + interval '15 days'
));
-- event
select fx_event(:'event6ID', :'group4ID', :'eventCategory2ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months'
        + interval '15 days'
));
-- event
select fx_event(:'event7ID', :'group1ID', :'eventCategory1ID', jsonb_build_object('starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month'
        + interval '15 days'));
-- event
select fx_event(:'event8ID', :'group2ID', :'eventCategory2ID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') + interval '15 days'
));

-- Event attendees (in the same months as the events they attend)
-- event1 (month_10): 3 attendees
-- event2 (month_8): 2 attendees
-- event3 (month_6): 2 attendees
-- event4 (month_4): 1 attendee
-- event5 (month_3): 2 attendees
-- event6 (month_2): 1 attendee
insert into event_attendee (event_id, user_id, created_at) values
    (
        :'event1ID',
        :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months'
            + interval '1 day'
    ),
    (
        :'event1ID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months'
            + interval '5 days'
    ),
    (
        :'event1ID',
        :'user3ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months'
            + interval '10 days'
    ),
    (
        :'event2ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months'
            + interval '1 day'
    ),
    (
        :'event2ID',
        :'user5ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months'
            + interval '5 days'
    ),
    (
        :'event3ID',
        :'user6ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months'
            + interval '1 day'
    ),
    (
        :'event3ID',
        :'user7ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months'
            + interval '5 days'
    ),
    (
        :'event4ID',
        :'user8ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months'
            + interval '1 day'
    ),
    (
        :'event5ID',
        :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months'
            + interval '1 day'
    ),
    (
        :'event5ID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months'
            + interval '5 days'
    ),
    (
        :'event6ID',
        :'user3ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months'
            + interval '1 day'
    );

-- Group page views
insert into group_views (day, group_id, total) values
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months',
        :'group1ID',
        10
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months',
        :'group2ID',
        8
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months',
        :'group3ID',
        6
    ),
    (current_date, :'group4ID', 4),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
        :'group5ID',
        99
    );

-- Event page views
insert into event_views (day, event_id, total) values
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months',
        :'event1ID',
        12
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months',
        :'event2ID',
        8
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months',
        :'event3ID',
        6
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months',
        :'event4ID',
        4
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
        :'event5ID',
        7
    ),
    (current_date, :'event6ID', 5),
    (current_date, :'event8ID', 3);

-- Community page views
insert into community_views (day, community_id, total) values
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months',
        :'communityID',
        11
    ),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months',
        :'communityID',
        9
    ),
    (current_date, :'communityID', 5),
    (
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
        :'community2ID',
        99
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete accurate JSON for test community
select is(
    get_community_stats(:'communityID'::uuid)::jsonb,
    (
        with
        -- Define the months used in test data relative to current_timestamp at UTC
        months as (
            select
                date_trunc('month', current_timestamp at time zone 'UTC') as m0,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '11 months' as m11,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' as m10,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months' as m9,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months' as m8,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months' as m7,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months' as m6,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' as m5,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' as m4,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' as m3,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' as m2
        ),
        days as (
            select current_date as d0
        )
        select jsonb_build_object(
            'groups', jsonb_build_object(
                'total', 4,
                'total_by_category', jsonb_build_array(
                    jsonb_build_array('AI/ML', 2),
                    jsonb_build_array('Cloud Native', 2)
                ),
                'total_by_region', jsonb_build_array(
                    jsonb_build_array('Europe', 2),
                    jsonb_build_array('North America', 2)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m9 at time zone 'UTC') * 1000)::bigint, 2),
                    jsonb_build_array((extract(epoch from m7 at time zone 'UTC') * 1000)::bigint, 3),
                    jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 4)
                ),
                'running_total_by_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m9 at time zone 'UTC') * 1000)::bigint, 2)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m7 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 2)
                    )
                ),
                'running_total_by_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m7 at time zone 'UTC') * 1000)::bigint, 2)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m9 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 2)
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m9, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m7, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m5, 'YYYY-MM'), 1)
                ),
                'per_month_by_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m9, 'YYYY-MM'), 1)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array(to_char(m7, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m5, 'YYYY-MM'), 1)
                    )
                ),
                'per_month_by_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m7, 'YYYY-MM'), 1)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array(to_char(m9, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m5, 'YYYY-MM'), 1)
                    )
                )
            ),
            'members', jsonb_build_object(
                'total', 8,
                'total_by_category', jsonb_build_array(
                    jsonb_build_array('AI/ML', 5),
                    jsonb_build_array('Cloud Native', 3)
                ),
                'total_by_region', jsonb_build_array(
                    jsonb_build_array('Europe', 5),
                    jsonb_build_array('North America', 3)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m11 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 2),
                    jsonb_build_array((extract(epoch from m9 at time zone 'UTC') * 1000)::bigint, 3),
                    jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 4),
                    jsonb_build_array((extract(epoch from m7 at time zone 'UTC') * 1000)::bigint, 5),
                    jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 6),
                    jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 7),
                    jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 8)
                ),
                'running_total_by_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m11 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m9 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 4),
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 5)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m7 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 3)
                    )
                ),
                'running_total_by_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m11 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m7 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 4),
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 5)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m9 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 3)
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m11, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m9, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m7, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m6, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m5, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m4, 'YYYY-MM'), 1)
                ),
                'per_month_by_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array(to_char(m11, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m9, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 1)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array(to_char(m7, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m5, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1)
                    )
                ),
                'per_month_by_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array(to_char(m11, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m7, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array(to_char(m9, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m5, 'YYYY-MM'), 1)
                    )
                )
            ),
            'events', jsonb_build_object(
                'total', 6,
                'total_by_event_category', jsonb_build_array(
                    jsonb_build_array('Conference', 3),
                    jsonb_build_array('Meetup', 3)
                ),
                'total_by_group_category', jsonb_build_array(
                    jsonb_build_array('AI/ML', 3),
                    jsonb_build_array('Cloud Native', 3)
                ),
                'total_by_group_region', jsonb_build_array(
                    jsonb_build_array('Europe', 4),
                    jsonb_build_array('North America', 2)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 2),
                    jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 3),
                    jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 4),
                    jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 5),
                    jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 6)
                ),
                'running_total_by_event_category', jsonb_build_object(
                    'Conference', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 3)
                    ),
                    'Meetup', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 3)
                    )
                ),
                'running_total_by_group_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 3)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 3)
                    )
                ),
                'running_total_by_group_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 4)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 2)
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m6, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                ),
                'per_month_by_event_category', jsonb_build_object(
                    'Conference', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 1)
                    ),
                    'Meetup', jsonb_build_array(
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                    )
                ),
                'per_month_by_group_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 1)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                    )
                ),
                'per_month_by_group_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 1)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                    )
                )
            ),
            'attendees', jsonb_build_object(
                'total', 11,
                'total_by_event_category', jsonb_build_array(
                    jsonb_build_array('Conference', 7),
                    jsonb_build_array('Meetup', 4)
                ),
                'total_by_group_category', jsonb_build_array(
                    jsonb_build_array('AI/ML', 7),
                    jsonb_build_array('Cloud Native', 4)
                ),
                'total_by_group_region', jsonb_build_array(
                    jsonb_build_array('Europe', 8),
                    jsonb_build_array('North America', 3)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 3),
                    jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 5),
                    jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 7),
                    jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 8),
                    jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 10),
                    jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 11)
                ),
                'running_total_by_event_category', jsonb_build_object(
                    'Conference', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 5),
                        jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 7)
                    ),
                    'Meetup', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 4)
                    )
                ),
                'running_total_by_group_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 5),
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 7)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 1),
                        jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 4)
                    )
                ),
                'running_total_by_group_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m10 at time zone 'UTC') * 1000)::bigint, 3),
                        jsonb_build_array((extract(epoch from m8 at time zone 'UTC') * 1000)::bigint, 5),
                        jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 6),
                        jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 8)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array((extract(epoch from m6 at time zone 'UTC') * 1000)::bigint, 2),
                        jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 3)
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m10, 'YYYY-MM'), 3),
                    jsonb_build_array(to_char(m8, 'YYYY-MM'), 2),
                    jsonb_build_array(to_char(m6, 'YYYY-MM'), 2),
                    jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 2),
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                ),
                'per_month_by_event_category', jsonb_build_object(
                    'Conference', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 3),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 2),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 2)
                    ),
                    'Meetup', jsonb_build_array(
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 2),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                    )
                ),
                'per_month_by_group_category', jsonb_build_object(
                    'AI/ML', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 3),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 2),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 2)
                    ),
                    'Cloud Native', jsonb_build_array(
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 2),
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                    )
                ),
                'per_month_by_group_region', jsonb_build_object(
                    'Europe', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 3),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 2),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 2)
                    ),
                    'North America', jsonb_build_array(
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 2),
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                    )
                )
            ),
            'page_views', jsonb_build_object(
                'total_views', 98,
                'total', jsonb_build_object(
                    'total_views', 98,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 17)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 33),
                        jsonb_build_array(to_char(m9, 'YYYY-MM'), 8),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 17),
                        jsonb_build_array(to_char(m7, 'YYYY-MM'), 6),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 6),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 4),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 7),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 17)
                    )
                ),
                'community', jsonb_build_object(
                    'total_views', 25,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 5)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 11),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 9),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 5)
                    )
                ),
                'events', jsonb_build_object(
                    'total_views', 45,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 8)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 12),
                        jsonb_build_array(to_char(m8, 'YYYY-MM'), 8),
                        jsonb_build_array(to_char(m6, 'YYYY-MM'), 6),
                        jsonb_build_array(to_char(m4, 'YYYY-MM'), 4),
                        jsonb_build_array(to_char(m3, 'YYYY-MM'), 7),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 8)
                    )
                ),
                'groups', jsonb_build_object(
                    'total_views', 28,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 4)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m10, 'YYYY-MM'), 10),
                        jsonb_build_array(to_char(m9, 'YYYY-MM'), 8),
                        jsonb_build_array(to_char(m7, 'YYYY-MM'), 6),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 4)
                    )
                )
            )
        )
        from months, days
    ),
    'Should return complete accurate JSON for test community'
);

-- Should return empty stats for unknown community
select is(
    get_community_stats(:'unknownCommunityID'::uuid)::jsonb,
    $$
    {
        "groups": {
            "total": 0,
            "total_by_category": [],
            "total_by_region": [],
            "running_total": [],
            "running_total_by_category": {},
            "running_total_by_region": {},
            "per_month": [],
            "per_month_by_category": {},
            "per_month_by_region": {}
        },
        "members": {
            "total": 0,
            "total_by_category": [],
            "total_by_region": [],
            "running_total": [],
            "running_total_by_category": {},
            "running_total_by_region": {},
            "per_month": [],
            "per_month_by_category": {},
            "per_month_by_region": {}
        },
        "events": {
            "total": 0,
            "total_by_event_category": [],
            "total_by_group_category": [],
            "total_by_group_region": [],
            "running_total": [],
            "running_total_by_event_category": {},
            "running_total_by_group_category": {},
            "running_total_by_group_region": {},
            "per_month": [],
            "per_month_by_event_category": {},
            "per_month_by_group_category": {},
            "per_month_by_group_region": {}
        },
        "attendees": {
            "total": 0,
            "total_by_event_category": [],
            "total_by_group_category": [],
            "total_by_group_region": [],
            "running_total": [],
            "running_total_by_event_category": {},
            "running_total_by_group_category": {},
            "running_total_by_group_region": {},
            "per_month": [],
            "per_month_by_event_category": {},
            "per_month_by_group_category": {},
            "per_month_by_group_region": {}
        },
        "page_views": {
            "total_views": 0,
            "total": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            },
            "community": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            },
            "events": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            },
            "groups": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            }
        }
    }
    $$::jsonb,
    'Should return empty stats for unknown community'
);

-- Should only count groups from the requested community
select is(
    (get_community_stats(:'communityID'::uuid)::jsonb->'groups'->>'total')::int,
    4,
    'Should only count groups from the requested community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
