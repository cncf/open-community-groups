-- Tests group dashboard statistics.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '3a120000-0000-0000-0000-000000000001'
\set communityID '3a120000-0000-0000-0000-000000000002'
\set event1ID '3a120000-0000-0000-0000-000000000003'
\set event2ID '3a120000-0000-0000-0000-000000000004'
\set event3ID '3a120000-0000-0000-0000-000000000005'
\set event4ID '3a120000-0000-0000-0000-000000000018'
\set eventCategory2ID '3a120000-0000-0000-0000-000000000006'
\set eventCategoryID '3a120000-0000-0000-0000-000000000007'
\set group1ID '3a120000-0000-0000-0000-000000000008'
\set group2ID '3a120000-0000-0000-0000-000000000009'
\set group3ID '3a120000-0000-0000-0000-000000000010'
\set group4ID '3a120000-0000-0000-0000-000000000020'
\set groupCategory2ID '3a120000-0000-0000-0000-000000000011'
\set groupCategoryID '3a120000-0000-0000-0000-000000000012'
\set nonExistentGroupID '3a120000-0000-0000-0000-000000000013'
\set periodCohostedEventID '3a120000-0000-0000-0000-000000000019'
\set periodEventID '3a120000-0000-0000-0000-000000000021'
\set periodGroupID '3a120000-0000-0000-0000-000000000022'
\set periodOldEventID '3a120000-0000-0000-0000-000000000023'
\set periodOwnerGroupID '3a120000-0000-0000-0000-000000000024'
\set periodUndatedCohostedEventID '3a120000-0000-0000-0000-000000000025'
\set periodUndatedEventID '3a120000-0000-0000-0000-000000000026'
\set user1ID '3a120000-0000-0000-0000-000000000014'
\set user2ID '3a120000-0000-0000-0000-000000000015'
\set user3ID '3a120000-0000-0000-0000-000000000016'
\set user4ID '3a120000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the seeded groups
select fx_community(:'communityID');

-- Second community owning a group outside the seeded scopes
select fx_community(:'community2ID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-get-group-stats'));
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-get-group-stats'));
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-get-group-stats'));
select fx_user(:'user4ID', jsonb_build_object('username', 'user4-get-group-stats'));

-- Event category of the community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category of the second community
select fx_event_category(:'eventCategory2ID', :'community2ID');

-- Group category of the community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the second community
select fx_group_category(:'groupCategory2ID', :'community2ID');

-- Top-level groups (using relative dates within 2-year window)
select fx_group(:'group1ID', :'communityID', :'groupCategoryID', jsonb_build_object('created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months'));
select fx_group(:'group3ID', :'community2ID', :'groupCategory2ID', jsonb_build_object('created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months'));

-- Child groups, one active and one inactive that subgroup stats exclude
select fx_group(:'group2ID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
    'parent_group_id', :'group1ID'
));
select fx_group(:'group4ID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
    'parent_group_id', :'group1ID'
));

-- Group whose stats span the start of the two-year period
select fx_group(:'periodGroupID', :'communityID', :'groupCategoryID');

-- Group owning the events co-hosted by the period group
select fx_group(:'periodOwnerGroupID', :'communityID', :'groupCategoryID');

-- Events (month -2 and current month)
select fx_event(:'event1ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '15 days'
));
select fx_event(:'event2ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') + interval '15 days'
));
select fx_event(:'event3ID', :'group3ID', :'eventCategory2ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') + interval '20 days'
));
select fx_event(:'event4ID', :'group4ID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') + interval '5 days'
));

-- Event co-hosted by the period group, starting the month before the period
select fx_event(:'periodCohostedEventID', :'periodOwnerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_date - interval '2 years') - interval '1 month' + interval '14 days'
));

-- Period group event starting the month after the period start
select fx_event(:'periodEventID', :'periodGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_date - interval '2 years') + interval '1 month' + interval '14 days'
));

-- Period group event starting the month before the period
select fx_event(:'periodOldEventID', :'periodGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_date - interval '2 years') - interval '1 month' + interval '14 days'
));

-- Undated event co-hosted by the period group
select fx_event(:'periodUndatedCohostedEventID', :'periodOwnerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', null
));

-- Undated period group event
select fx_event(:'periodUndatedEventID', :'periodGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', null
));

-- Members (month -3 and month -1 relative to current date)
insert into group_member (group_id, user_id, created_at) values
    (
        :'group1ID',
        :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '5 days'
    ), (
        :'group1ID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '10 days'
    ), (
        :'group2ID',
        :'user3ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '15 days'
    ), (
        :'group2ID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '1 day'
    ), (
        :'group4ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '20 days'
    );

-- Period group members, one joined before the period and one last month
insert into group_member (group_id, user_id, created_at) values
    (
        :'periodGroupID',
        :'user1ID',
        date_trunc('month', current_date - interval '2 years') - interval '1 month' + interval '14 days'
    ), (
        :'periodGroupID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '14 days'
    );

-- Page views
insert into group_views (day, group_id, total) values
    (date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months', :'group1ID', 4),
    (current_date, :'group1ID', 6),
    (current_date, :'group2ID', 10),
    (current_date, :'group4ID', 100);

-- Period group views on the day before the period start, the period start
-- day, and today
insert into group_views (day, group_id, total) values
    ((current_date - interval '2 years')::date - 1, :'periodGroupID', 8),
    ((current_date - interval '2 years')::date, :'periodGroupID', 16),
    (current_date, :'periodGroupID', 32);

-- Attendees (matching event months)
insert into event_attendee (event_id, user_id, created_at) values
    (
        :'event1ID',
        :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '1 day'
    ), (
        :'event1ID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '5 days'
    ), (
        :'event2ID',
        :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '10 days'
    ), (
        :'event3ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '20 days'
    ), (
        :'event4ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '5 days'
    );

-- Period group attendees, one registered before the period for an event in
-- it and one registered last month for the undated event
insert into event_attendee (event_id, user_id, created_at) values
    (
        :'periodEventID',
        :'user1ID',
        date_trunc('month', current_date - interval '2 years') - interval '1 month' + interval '20 days'
    ), (
        :'periodUndatedEventID',
        :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '20 days'
    );

-- Approved co-host rows of the period group
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'periodCohostedEventID', :'periodGroupID'),
    (current_timestamp, 'approved', :'periodUndatedCohostedEventID', :'periodGroupID');

-- Event views aggregated into group analytics
insert into event_views (day, event_id, total) values
    (date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months', :'event1ID', 7),
    (current_date, :'event2ID', 5),
    (current_date, :'event3ID', 9),
    (current_date, :'event4ID', 100);

-- Period group event views on the day before the period start, the period
-- start day, and today
insert into event_views (day, event_id, total) values
    ((current_date - interval '2 years')::date - 1, :'periodOldEventID', 1),
    ((current_date - interval '2 years')::date, :'periodEventID', 2),
    (current_date, :'periodEventID', 4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should aggregate subgroup stats with unique members
select is(
    get_group_stats(:'communityID'::uuid, :'group1ID'::uuid, true)::jsonb,
    (
        with
        -- Define the months used in test data relative to current_timestamp at UTC
        months as (
            select
                date_trunc('month', current_timestamp at time zone 'UTC') as m0,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' as m2,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' as m3
        ),
        days as (
            select current_date as d0
        )
        select jsonb_build_object(
            'members', jsonb_build_object(
                'total', 3,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m3 at time zone 'UTC') * 1000)::bigint,
                        1
                    ),
                    jsonb_build_array(
                        (extract(epoch from m1 at time zone 'UTC') * 1000)::bigint,
                        3
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m1, 'YYYY-MM'), 2)
                )
            ),
            'events', jsonb_build_object(
                'total', 1,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m2 at time zone 'UTC') * 1000)::bigint,
                        1
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                )
            ),
            'cohosted_events', jsonb_build_object(
                'total', 0,
                'running_total', jsonb_build_array(),
                'per_month', jsonb_build_array()
            ),
            'attendees', jsonb_build_object(
                'total', 2,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m2 at time zone 'UTC') * 1000)::bigint,
                        2
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 2)
                )
            ),
            'page_views', jsonb_build_object(
                'total_views', 32,
                'total', jsonb_build_object(
                    'total_views', 32,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 21)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 11),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 21)
                    )
                ),
                'events', jsonb_build_object(
                    'total_views', 12,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 5)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 7),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 5)
                    )
                ),
                'group', jsonb_build_object(
                    'total_views', 20,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 16)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 4),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 16)
                    )
                )
            )
        )
        from months, days
    ),
    'Should aggregate subgroup stats with unique members'
);

-- Should bucket attendees by registration date across the period start
select is(
    get_group_stats(:'communityID'::uuid, :'periodGroupID'::uuid, false)::jsonb->'attendees',
    (
        -- Registration months before the period and last month at UTC
        with months as (
            select
                date_trunc('month', current_date - interval '2 years') - interval '1 month' as before_period,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1
        )
        select jsonb_build_object(
            'total', 2,
            'running_total', jsonb_build_array(
                jsonb_build_array((extract(epoch from before_period at time zone 'UTC') * 1000)::bigint, 1),
                jsonb_build_array((extract(epoch from m1 at time zone 'UTC') * 1000)::bigint, 2)
            ),
            'per_month', jsonb_build_array(
                jsonb_build_array(to_char(m1, 'YYYY-MM'), 1)
            )
        )
        from months
    ),
    'Should bucket attendees by registration date across the period start'
);

-- Should bucket events by start date and keep undated events in totals only
select is(
    jsonb_build_object(
        'cohosted_events', get_group_stats(:'communityID'::uuid, :'periodGroupID'::uuid, false)::jsonb->'cohosted_events',
        'events', get_group_stats(:'communityID'::uuid, :'periodGroupID'::uuid, false)::jsonb->'events'
    ),
    (
        -- Start months before and after the period start at UTC
        with months as (
            select
                date_trunc('month', current_date - interval '2 years') + interval '1 month' as after_period_start,
                date_trunc('month', current_date - interval '2 years') - interval '1 month' as before_period
        )
        select jsonb_build_object(
            'cohosted_events', jsonb_build_object(
                'total', 2,
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from before_period at time zone 'UTC') * 1000)::bigint, 1)
                ),
                'per_month', jsonb_build_array()
            ),
            'events', jsonb_build_object(
                'total', 3,
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from before_period at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from after_period_start at time zone 'UTC') * 1000)::bigint, 2)
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(after_period_start, 'YYYY-MM'), 1)
                )
            )
        )
        from months
    ),
    'Should bucket events by start date and keep undated events in totals only'
);

-- Should bucket members by first membership across the period start
select is(
    get_group_stats(:'communityID'::uuid, :'periodGroupID'::uuid, false)::jsonb->'members',
    (
        -- Membership months before the period and last month at UTC
        with months as (
            select
                date_trunc('month', current_date - interval '2 years') - interval '1 month' as before_period,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1
        )
        select jsonb_build_object(
            'total', 2,
            'running_total', jsonb_build_array(
                jsonb_build_array((extract(epoch from before_period at time zone 'UTC') * 1000)::bigint, 1),
                jsonb_build_array((extract(epoch from m1 at time zone 'UTC') * 1000)::bigint, 2)
            ),
            'per_month', jsonb_build_array(
                jsonb_build_array(to_char(m1, 'YYYY-MM'), 1)
            )
        )
        from months
    ),
    'Should bucket members by first membership across the period start'
);

-- Should merge event and group page views across the period start
select is(
    get_group_stats(:'communityID'::uuid, :'periodGroupID'::uuid, false)::jsonb->'page_views',
    (
        -- Labels of the period start month, today, and the current month
        with labels as (
            select
                to_char(current_date, 'YYYY-MM') as current_month,
                to_char((current_date - interval '2 years')::date, 'YYYY-MM') as period_start_month,
                to_char(current_date, 'YYYY-MM-DD') as today
        )
        select jsonb_build_object(
            'total_views', 63,
            'total', jsonb_build_object(
                'total_views', 63,
                'per_day_views', jsonb_build_array(
                    jsonb_build_array(today, 36)
                ),
                'per_month_views', jsonb_build_array(
                    jsonb_build_array(period_start_month, 18),
                    jsonb_build_array(current_month, 36)
                )
            ),
            'events', jsonb_build_object(
                'total_views', 7,
                'per_day_views', jsonb_build_array(
                    jsonb_build_array(today, 4)
                ),
                'per_month_views', jsonb_build_array(
                    jsonb_build_array(period_start_month, 2),
                    jsonb_build_array(current_month, 4)
                )
            ),
            'group', jsonb_build_object(
                'total_views', 56,
                'per_day_views', jsonb_build_array(
                    jsonb_build_array(today, 32)
                ),
                'per_month_views', jsonb_build_array(
                    jsonb_build_array(period_start_month, 16),
                    jsonb_build_array(current_month, 32)
                )
            )
        )
        from labels
    ),
    'Should merge event and group page views across the period start'
);

-- Should return complete accurate JSON for seeded group
select is(
    get_group_stats(:'communityID'::uuid, :'group1ID'::uuid, false)::jsonb,
    (
        with
        -- Define the months used in test data relative to current_timestamp at UTC
        months as (
            select
                date_trunc('month', current_timestamp at time zone 'UTC') as m0,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' as m2,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' as m3
        ),
        days as (
            select current_date as d0
        )
        select jsonb_build_object(
            'members', jsonb_build_object(
                'total', 2,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m3 at time zone 'UTC') * 1000)::bigint,
                        1
                    ),
                    jsonb_build_array(
                        (extract(epoch from m1 at time zone 'UTC') * 1000)::bigint,
                        2
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m1, 'YYYY-MM'), 1)
                )
            ),
            'events', jsonb_build_object(
                'total', 1,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m2 at time zone 'UTC') * 1000)::bigint,
                        1
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                )
            ),
            'cohosted_events', jsonb_build_object(
                'total', 0,
                'running_total', jsonb_build_array(),
                'per_month', jsonb_build_array()
            ),
            'attendees', jsonb_build_object(
                'total', 2,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m2 at time zone 'UTC') * 1000)::bigint,
                        2
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 2)
                )
            ),
            'page_views', jsonb_build_object(
                'total_views', 22,
                'total', jsonb_build_object(
                    'total_views', 22,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 11)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 11),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 11)
                    )
                ),
                'events', jsonb_build_object(
                    'total_views', 12,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 5)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 7),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 5)
                    )
                ),
                'group', jsonb_build_object(
                    'total_views', 10,
                    'per_day_views', jsonb_build_array(
                        jsonb_build_array(to_char(d0, 'YYYY-MM-DD'), 6)
                    ),
                    'per_month_views', jsonb_build_array(
                        jsonb_build_array(to_char(m2, 'YYYY-MM'), 4),
                        jsonb_build_array(to_char(m0, 'YYYY-MM'), 6)
                    )
                )
            )
        )
        from months, days
    ),
    'Should return complete accurate JSON for seeded group'
);

-- Should return empty stats for unknown group
select is(
    get_group_stats(:'communityID'::uuid, :'nonExistentGroupID'::uuid, false)::jsonb,
    $$
    {
        "members": {
            "total": 0,
            "running_total": [],
            "per_month": []
        },
        "events": {
            "total": 0,
            "running_total": [],
            "per_month": []
        },
        "cohosted_events": {
            "total": 0,
            "running_total": [],
            "per_month": []
        },
        "attendees": {
            "total": 0,
            "running_total": [],
            "per_month": []
        },
        "page_views": {
            "total_views": 0,
            "total": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            },
            "events": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            },
            "group": {
                "total_views": 0,
                "per_day_views": [],
                "per_month_views": []
            }
        }
    }
    $$,
    'Should return empty stats for unknown group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
