-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '9a050000-0000-0000-0000-000000000001'
\set community2ID '9a050000-0000-0000-0000-000000000002'
\set community3ID '9a050000-0000-0000-0000-000000000003'
\set event1ID '9a050000-0000-0000-0000-000000000004'
\set event2ID '9a050000-0000-0000-0000-000000000005'
\set event3ID '9a050000-0000-0000-0000-000000000006'
\set event4ID '9a050000-0000-0000-0000-000000000007'
\set event5ID '9a050000-0000-0000-0000-000000000008'
\set eventCategory2ID '9a050000-0000-0000-0000-000000000009'
\set eventCategory3ID '9a050000-0000-0000-0000-000000000010'
\set eventCategoryID '9a050000-0000-0000-0000-000000000011'
\set group1ID '9a050000-0000-0000-0000-000000000012'
\set group2ID '9a050000-0000-0000-0000-000000000013'
\set group3ID '9a050000-0000-0000-0000-000000000014'
\set group4ID '9a050000-0000-0000-0000-000000000015'
\set groupCategory2ID '9a050000-0000-0000-0000-000000000016'
\set groupCategory3ID '9a050000-0000-0000-0000-000000000017'
\set groupCategoryID '9a050000-0000-0000-0000-000000000018'
\set user1ID '9a050000-0000-0000-0000-000000000019'
\set user2ID '9a050000-0000-0000-0000-000000000020'
\set user3ID '9a050000-0000-0000-0000-000000000021'
\set user4ID '9a050000-0000-0000-0000-000000000022'
\set user5ID '9a050000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline active communities, categories and users for site stats
select fx_community(:'community1ID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'community1ID');
select fx_group_category(:'groupCategory2ID', :'community2ID');
select fx_event_category(:'eventCategoryID', :'community1ID');
select fx_event_category(:'eventCategory2ID', :'community2ID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');
select fx_user(:'user5ID');

-- Inactive community with otherwise-countable rows
select fx_community(:'community3ID', jsonb_build_object('active', false));
select fx_group_category(:'groupCategory3ID', :'community3ID');
select fx_event_category(:'eventCategory3ID', :'community3ID');

-- Groups covering active, deleted and inactive-community stats states
select fx_group(:'group1ID', :'community1ID', :'groupCategoryID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' + interval '10 days'
));
select fx_group(:'group2ID', :'community2ID', :'groupCategory2ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '10 days'
));
select fx_group(:'group3ID', :'community1ID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '10 days',
    'deleted', true
));
select fx_group(:'group4ID', :'community3ID', :'groupCategory3ID', jsonb_build_object(
    'created_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' + interval '15 days'
));

-- Group members
-- month_4: user1 joins group1
-- month_3: user2 joins group1
-- month_2: user3 joins group2
-- month_1: user4 joins group3 (deleted group)
-- month_1: user5 joins group4 (inactive community)
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '4 months' + interval '5 days'),
    (:'group1ID', :'user2ID',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '3 months' + interval '5 days'),
    (:'group2ID', :'user3ID',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '2 months' + interval '5 days'),
    (:'group3ID', :'user4ID',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '5 days'),
    (:'group4ID', :'user5ID',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '8 days');

-- Events
-- month_4: event1 (published)
-- month_1: event2 (published)
-- null: event3 (published, no start)
-- month_1: event4 (unpublished)
-- month_1: event5 (published, inactive community)
select fx_event(:'event1ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '12 days'
));
select fx_event(:'event2ID', :'group2ID', :'eventCategory2ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '12 days'
));
select fx_event(:'event3ID', :'group1ID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'event4ID', :'group1ID', :'eventCategoryID', jsonb_build_object(
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '6 days'
));
select fx_event(:'event5ID', :'group4ID', :'eventCategory3ID', jsonb_build_object(
    'published', true,
    'starts_at', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '9 days'
));

-- Event attendees
-- month_4: attendee1
-- month_3: attendee2
-- month_2: attendee3
-- month_1: attendee4
-- month_1: attendee5 (unpublished event)
-- month_1: attendee6 (inactive community event)
-- month_1: attendee7 (non-confirmed status)
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'event1ID', :'user1ID', 'confirmed',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '4 months' + interval '1 day'),
    (:'event1ID', :'user2ID', 'confirmed',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '3 months' + interval '1 day'),
    (:'event3ID', :'user3ID', 'confirmed',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '2 months' + interval '1 day'),
    (:'event2ID', :'user4ID', 'confirmed',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '1 day'),
    (:'event4ID', :'user5ID', 'confirmed',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '3 days'),
    (:'event5ID', :'user1ID', 'confirmed',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '4 days'),
    (:'event1ID', :'user3ID', 'invitation-pending',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '5 days');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct site stats as JSON
select is(
    get_site_stats()::jsonb,
    (
        with months as (
            select
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' as m5,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' as m4,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' as m3,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' as m2,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1
        )
        select jsonb_build_object(
            'groups', jsonb_build_object(
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m5, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 1)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m5 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 2)
                ),
                'total', 2
            ),
            'members', jsonb_build_object(
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 2),
                    jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 3)
                ),
                'total', 3
            ),
            'events', jsonb_build_object(
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m1, 'YYYY-MM'), 1)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m1 at time zone 'UTC') * 1000)::bigint, 2)
                ),
                'total', 3
            ),
            'attendees', jsonb_build_object(
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m4, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m3, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m1, 'YYYY-MM'), 1)
                ),
                'running_total', jsonb_build_array(
                    jsonb_build_array((extract(epoch from m4 at time zone 'UTC') * 1000)::bigint, 1),
                    jsonb_build_array((extract(epoch from m3 at time zone 'UTC') * 1000)::bigint, 2),
                    jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 3),
                    jsonb_build_array((extract(epoch from m1 at time zone 'UTC') * 1000)::bigint, 4)
                ),
                'total', 4
            )
        )
        from months
    ),
    'Should return correct site stats as JSON'
);

-- Should exclude deleted groups and unpublished events
select is(
    (get_site_stats()::jsonb->'groups'->>'total')::int,
    2,
    'Should exclude deleted groups from totals'
);

select is(
    (get_site_stats()::jsonb->'events'->>'total')::int,
    3,
    'Should exclude unpublished events from totals'
);

-- Should exclude data from inactive communities
select is(
    (get_site_stats()::jsonb->'members'->>'total')::int,
    3,
    'Should exclude members of groups in inactive communities from totals'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
