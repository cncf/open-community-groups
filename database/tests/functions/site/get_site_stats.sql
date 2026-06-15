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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
)
values
    (
        :'community1ID',
        'site-stats-community-one',
        'Site Stats Community One',
        'Site stats community 1',
        'https://example.com/site-stats-banner-mobile1.png',
        'https://example.com/site-stats-banner1.png',
        'https://example.com/site-stats-logo1.png'
    ),
    (
        :'community2ID',
        'site-stats-community-two',
        'Site Stats Community Two',
        'Site stats community 2',
        'https://example.com/site-stats-banner-mobile2.png',
        'https://example.com/site-stats-banner2.png',
        'https://example.com/site-stats-logo2.png'
    );

-- Inactive community
insert into community (
    community_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community3ID',
    'inactive-site-stats-community',
    'Inactive Site Stats Community',
    'Inactive site stats community',
    false,
    'https://example.com/inactive-site-stats-banner-mobile.png',
    'https://example.com/inactive-site-stats-banner.png',
    'https://example.com/inactive-site-stats-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'community1ID', 'General'),
    (:'groupCategory2ID', :'community2ID', 'General'),
    (:'groupCategory3ID', :'community3ID', 'General');

-- Event category
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategoryID', :'community1ID', 'Meetup'),
    (:'eventCategory2ID', :'community2ID', 'Meetup'),
    (:'eventCategory3ID', :'community3ID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'hash-1', 'site-stats-user1@example.com', true, 'site-stats-user1'),
    (:'user2ID', 'hash-2', 'site-stats-user2@example.com', true, 'site-stats-user2'),
    (:'user3ID', 'hash-3', 'site-stats-user3@example.com', true, 'site-stats-user3'),
    (:'user4ID', 'hash-4', 'site-stats-user4@example.com', true, 'site-stats-user4'),
    (:'user5ID', 'hash-5', 'site-stats-user5@example.com', true, 'site-stats-user5');

-- Group
-- month_5: group1 (active)
-- month_3: group2 (active)
-- month_2: group3 (deleted)
-- month_5: group4 (active, inactive community)
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
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '5 months' + interval '10 days',
        true, false),
    (:'group2ID', :'community2ID', :'groupCategory2ID', 'Group Two', 'group-two',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '3 months' + interval '10 days',
        true, false),
    (:'group3ID', :'community1ID', :'groupCategoryID', 'Group Three', 'group-three',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '2 months' + interval '10 days',
        false, true),
    (:'group4ID', :'community3ID', :'groupCategory3ID', 'Group Four', 'group-four',
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '5 months' + interval '15 days',
        true, false);

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
    (:'event1ID', :'group1ID', :'eventCategoryID', 'in-person',
        'Event One', 'event-one', 'Event 1', 'UTC',
        true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '4 months' + interval '12 days'),
    (:'event2ID', :'group2ID', :'eventCategory2ID', 'in-person',
        'Event Two', 'event-two', 'Event 2', 'UTC',
        true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '12 days'),
    (:'event3ID', :'group1ID', :'eventCategoryID', 'in-person',
        'Event Three', 'event-three', 'Event 3', 'UTC',
        true, false, false,
        null),
    (:'event4ID', :'group1ID', :'eventCategoryID', 'in-person',
        'Event Four', 'event-four', 'Event 4', 'UTC',
        false, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '6 days'),
    (:'event5ID', :'group4ID', :'eventCategory3ID', 'in-person',
        'Event Five', 'event-five', 'Event 5', 'UTC',
        true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC')
            - interval '1 month' + interval '9 days');

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
