-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set event1ID '00000000-0000-0000-0000-000000000101'
\set event2ID '00000000-0000-0000-0000-000000000102'
\set event3ID '00000000-0000-0000-0000-000000000103'
\set event4ID '00000000-0000-0000-0000-000000000104'
\set eventCategory2ID '00000000-0000-0000-0000-000000000302'
\set eventCategoryID '00000000-0000-0000-0000-000000000301'
\set group1ID '00000000-0000-0000-0000-000000000201'
\set group2ID '00000000-0000-0000-0000-000000000202'
\set group3ID '00000000-0000-0000-0000-000000000203'
\set groupCategory2ID '00000000-0000-0000-0000-000000000402'
\set groupCategoryID '00000000-0000-0000-0000-000000000401'
\set user1ID '00000000-0000-0000-0000-000000000501'
\set user2ID '00000000-0000-0000-0000-000000000502'
\set user3ID '00000000-0000-0000-0000-000000000503'
\set user4ID '00000000-0000-0000-0000-000000000504'
\set user5ID '00000000-0000-0000-0000-000000000505'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values
    (:'community1ID', 'community-one', 'Community One', 'Test community 1', 'https://example.com/logo1.png', 'https://example.com/banner_mobile1.png', 'https://example.com/banner1.png'),
    (:'community2ID', 'community-two', 'Community Two', 'Test community 2', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- Group Category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'community1ID', 'General'),
    (:'groupCategory2ID', :'community2ID', 'General');

-- Event Category
insert into event_category (event_category_id, community_id, name, slug)
values
    (:'eventCategoryID', :'community1ID', 'Meetup', 'meetup'),
    (:'eventCategory2ID', :'community2ID', 'Meetup', 'meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', 'hash-2', 'user2@example.com', 'user2'),
    (:'user3ID', 'hash-3', 'user3@example.com', 'user3'),
    (:'user4ID', 'hash-4', 'user4@example.com', 'user4'),
    (:'user5ID', 'hash-5', 'user5@example.com', 'user5');

-- Groups
-- month_5: group1 (active)
-- month_3: group2 (active)
-- month_2: group3 (deleted)
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
    (:'group1ID', :'community1ID', :'groupCategoryID', 'Group One', 'group-one',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' + interval '10 days',
        true, false),
    (:'group2ID', :'community2ID', :'groupCategory2ID', 'Group Two', 'group-two',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '10 days',
        true, false),
    (:'group3ID', :'community1ID', :'groupCategoryID', 'Group Three', 'group-three',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '10 days',
        false, true);

-- Group Members
-- month_4: user1 joins group1
-- month_3: user2 joins group1
-- month_2: user3 joins group2
-- month_1: user4 joins group3 (deleted group)
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '5 days'),
    (:'group1ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '5 days'),
    (:'group2ID', :'user3ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '5 days'),
    (:'group3ID', :'user4ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '5 days');

-- Events
-- month_4: event1 (published)
-- month_1: event2 (published)
-- null: event3 (published, no start)
-- month_1: event4 (unpublished)
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
    (:'event1ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event One', 'event-one', 'Event 1', 'UTC',
        true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '12 days'),
    (:'event2ID', :'group2ID', :'eventCategory2ID', 'in-person', 'Event Two', 'event-two', 'Event 2', 'UTC',
        true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '12 days'),
    (:'event3ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event Three', 'event-three', 'Event 3', 'UTC',
        true, false, false,
        null),
    (:'event4ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event Four', 'event-four', 'Event 4', 'UTC',
        false, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '6 days');

-- Event Attendees
-- month_4: attendee1
-- month_3: attendee2
-- month_2: attendee3
-- month_1: attendee4
-- month_1: attendee5 (unpublished event)
insert into event_attendee (event_id, user_id, created_at)
values
    (:'event1ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '1 day'),
    (:'event1ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '1 day'),
    (:'event3ID', :'user3ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '1 day'),
    (:'event2ID', :'user4ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '1 day'),
    (:'event4ID', :'user5ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '3 days');

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
