-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set community2ID '3a120000-0000-0000-0000-000000000001'
\set communityID '3a120000-0000-0000-0000-000000000002'
\set event1ID '3a120000-0000-0000-0000-000000000003'
\set event2ID '3a120000-0000-0000-0000-000000000004'
\set event3ID '3a120000-0000-0000-0000-000000000005'
\set event4ID '3a120000-0000-0000-0000-000000000018'
\set event5ID '3a120000-0000-0000-0000-000000000019'
\set eventCategory2ID '3a120000-0000-0000-0000-000000000006'
\set eventCategoryID '3a120000-0000-0000-0000-000000000007'
\set group1ID '3a120000-0000-0000-0000-000000000008'
\set group2ID '3a120000-0000-0000-0000-000000000009'
\set group3ID '3a120000-0000-0000-0000-000000000010'
\set group4ID '3a120000-0000-0000-0000-000000000020'
\set group5ID '3a120000-0000-0000-0000-000000000021'
\set groupCategory2ID '3a120000-0000-0000-0000-000000000011'
\set groupCategoryID '3a120000-0000-0000-0000-000000000012'
\set nonExistentGroupID '3a120000-0000-0000-0000-000000000013'
\set user1ID '3a120000-0000-0000-0000-000000000014'
\set user2ID '3a120000-0000-0000-0000-000000000015'
\set user3ID '3a120000-0000-0000-0000-000000000016'
\set user4ID '3a120000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'communityID',
        'test-community',
        'Test Community',
        'Community used for group stats tests',
        'https://example.com/banner-mobile.png',
        'https://example.com/banner.png',
        'https://example.com/logo.png'
    ), (
        :'community2ID',
        'other-community',
        'Other Community',
        'Separate community for isolation testing',
        'https://example.com/banner-mobile-2.png',
        'https://example.com/banner-2.png',
        'https://example.com/logo-2.png'
    );

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech'),
    (:'groupCategory2ID', :'community2ID', 'Tech2');

-- Event categories
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Conference'),
    (:'eventCategory2ID', :'community2ID', 'Conference2');

-- Top-level groups (using relative dates within 2-year window)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    active,
    deleted
) values
    (:'group1ID', :'communityID', :'groupCategoryID', 'Group One', 'group-one',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months', true, false),
    (:'group3ID', :'community2ID', :'groupCategory2ID', 'Other Community Group', 'other-group',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months', true, false);

-- Child groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    active,
    deleted,

    parent_group_id
) values
    (
        :'group2ID',
        :'communityID',
        :'groupCategoryID',
        'Group Two',
        'group-two',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
        true,
        false,

        :'group1ID'
    ), (
        :'group4ID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Child Group',
        'inactive-child-group',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
        false,
        false,

        :'group1ID'
    ), (
        :'group5ID',
        :'communityID',
        :'groupCategoryID',
        'Deleted Child Group',
        'deleted-child-group',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months',
        false,
        true,

        :'group1ID'
    );

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', 'hash-2', 'user2@example.com', 'user2'),
    (:'user3ID', 'hash-3', 'user3@example.com', 'user3'),
    (:'user4ID', 'hash-4', 'user4@example.com', 'user4');

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
    ), (
        :'group5ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '20 days'
    );

-- Events (month -2 and current month)
insert into event (
    event_id,
    group_id,
    event_category_id,
    event_kind_id,
    name,
    slug,
    description,
    timezone,
    published,
    canceled,
    deleted,
    starts_at
) values
    (
        :'event1ID',
        :'group1ID',
        :'eventCategoryID',
        'in-person',
        'Event One',
        'event-one',
        'First event',
        'UTC',
        true,
        false,
        false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '15 days'
    ), (
        :'event2ID',
        :'group1ID',
        :'eventCategoryID',
        'in-person',
        'Event Two',
        'event-two',
        'Second event',
        'UTC',
        true,
        true,
        false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '15 days'
    ), (
        :'event3ID',
        :'group3ID',
        :'eventCategory2ID',
        'in-person',
        'Other Group Event',
        'other-event',
        'Other group event',
        'UTC',
        true,
        false,
        false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '20 days'
    ), (
        :'event4ID',
        :'group4ID',
        :'eventCategoryID',
        'in-person',
        'Inactive Child Event',
        'inactive-child-event',
        'Inactive child event',
        'UTC',
        true,
        false,
        false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '5 days'
    ), (
        :'event5ID',
        :'group5ID',
        :'eventCategoryID',
        'in-person',
        'Deleted Child Event',
        'deleted-child-event',
        'Deleted child event',
        'UTC',
        true,
        false,
        false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '5 days'
    );

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
    ), (
        :'event5ID',
        :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '5 days'
    );

-- Page views
insert into group_views (day, group_id, total) values
    (date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months', :'group1ID', 4),
    (current_date, :'group1ID', 6),
    (current_date, :'group2ID', 10),
    (current_date, :'group4ID', 100),
    (current_date, :'group5ID', 100);

-- Event views aggregated into group analytics
insert into event_views (day, event_id, total) values
    (date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months', :'event1ID', 7),
    (current_date, :'event2ID', 5),
    (current_date, :'event3ID', 9),
    (current_date, :'event4ID', 100),
    (current_date, :'event5ID', 100);

-- ============================================================================
-- TESTS
-- ============================================================================

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
