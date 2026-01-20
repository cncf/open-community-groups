-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000301'
\set event2ID '00000000-0000-0000-0000-000000000302'
\set event3ID '00000000-0000-0000-0000-000000000303'
\set event4ID '00000000-0000-0000-0000-000000000304'
\set event5ID '00000000-0000-0000-0000-000000000305'
\set event6ID '00000000-0000-0000-0000-000000000306'
\set event7ID '00000000-0000-0000-0000-000000000307'
\set event8ID '00000000-0000-0000-0000-000000000308'
\set eventCategory1ID '00000000-0000-0000-0000-000000000031'
\set eventCategory2ID '00000000-0000-0000-0000-000000000032'
\set group1ID '00000000-0000-0000-0000-000000000101'
\set group2ID '00000000-0000-0000-0000-000000000102'
\set group3ID '00000000-0000-0000-0000-000000000103'
\set group4ID '00000000-0000-0000-0000-000000000104'
\set group5ID '00000000-0000-0000-0000-000000000105'
\set nonExistentCommunityID '00000000-0000-0000-0000-999999999999'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'
\set region3ID '00000000-0000-0000-0000-000000000023'
\set user1ID '00000000-0000-0000-0000-000000000201'
\set user2ID '00000000-0000-0000-0000-000000000202'
\set user3ID '00000000-0000-0000-0000-000000000203'
\set user4ID '00000000-0000-0000-0000-000000000204'
\set user5ID '00000000-0000-0000-0000-000000000205'
\set user6ID '00000000-0000-0000-0000-000000000206'
\set user7ID '00000000-0000-0000-0000-000000000207'
\set user8ID '00000000-0000-0000-0000-000000000208'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'communityID', 'test-community', 'Test Community', 'Community used for dashboard stats tests', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'other-community', 'Other Community', 'Separate community for isolation testing', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- Regions
insert into region (region_id, community_id, name, "order") values
    (:'region1ID', :'communityID', 'Europe', 1),
    (:'region2ID', :'communityID', 'North America', 2),
    (:'region3ID', :'community2ID', 'South America', 1);

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'category1ID', :'communityID', 'AI/ML'),
    (:'category2ID', :'communityID', 'Cloud Native'),
    (:'category3ID', :'community2ID', 'Security');

-- Event categories
insert into event_category (event_category_id, community_id, name, slug) values
    (:'eventCategory1ID', :'communityID', 'Conference', 'conference'),
    (:'eventCategory2ID', :'communityID', 'Meetup', 'meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', 'hash-2', 'user2@example.com', 'user2'),
    (:'user3ID', 'hash-3', 'user3@example.com', 'user3'),
    (:'user4ID', 'hash-4', 'user4@example.com', 'user4'),
    (:'user5ID', 'hash-5', 'user5@example.com', 'user5'),
    (:'user6ID', 'hash-6', 'user6@example.com', 'user6'),
    (:'user7ID', 'hash-7', 'user7@example.com', 'user7'),
    (:'user8ID', 'hash-8', 'user8@example.com', 'user8');

-- Groups (using relative dates within 2-year window)
-- month_10 = date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' (group1, AI/ML, Europe)
-- month_9  = date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months'  (group2, AI/ML, North America)
-- month_7  = date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months'  (group3, Cloud Native, Europe)
-- month_5  = date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months'  (group4, Cloud Native, North America)
-- month_3  = date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months'  (group5, other community)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    region_id,
    active,
    deleted
) values
    (:'group1ID', :'communityID', :'category1ID', 'AI Europe', 'ai-europe',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' + interval '15 days',
        :'region1ID', true, false),
    (:'group2ID', :'communityID', :'category1ID', 'AI North America', 'ai-north-america',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months' + interval '15 days',
        :'region2ID', true, false),
    (:'group3ID', :'communityID', :'category2ID', 'Cloud Europe', 'cloud-europe',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months' + interval '15 days',
        :'region1ID', true, false),
    (:'group4ID', :'communityID', :'category2ID', 'Cloud North America', 'cloud-north-america',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' + interval '15 days',
        :'region2ID', true, false),
    (:'group5ID', :'community2ID', :'category3ID', 'Other Community Group', 'other-group',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '15 days',
        :'region3ID', true, false);

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
    (:'group1ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '11 months' + interval '20 days'),
    (:'group1ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' + interval '10 days'),
    (:'group2ID', :'user4ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '9 months' + interval '20 days'),
    (:'group2ID', :'user5ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months' + interval '10 days'),
    (:'group3ID', :'user6ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '7 months' + interval '20 days'),
    (:'group1ID', :'user3ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months' + interval '5 days'),
    (:'group4ID', :'user8ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '5 months' + interval '20 days'),
    (:'group3ID', :'user7ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '10 days');

-- Events
-- Published events across different months:
-- month_10: event1 (group1/AI/ML/Europe, Conference)
-- month_8:  event2 (group1/AI/ML/Europe, Meetup)
-- month_6:  event3 (group2/AI/ML/N.America, Conference)
-- month_4:  event4 (group3/Cloud/Europe, Meetup)
-- month_3:  event5 (group3/Cloud/Europe, Conference)
-- month_2:  event6 (group4/Cloud/N.America, Meetup)
-- Unpublished/canceled events (should not be counted):
-- month_1:  event7 (unpublished)
-- month_0:  event8 (canceled)
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
    (:'event1ID', :'group1ID', :'eventCategory1ID', 'in-person', 'Conference 1', 'conference-1', 'Event 1', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' + interval '15 days'),
    (:'event2ID', :'group1ID', :'eventCategory2ID', 'in-person', 'Meetup 1', 'meetup-1', 'Event 2', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months' + interval '15 days'),
    (:'event3ID', :'group2ID', :'eventCategory1ID', 'in-person', 'Conference 2', 'conference-2', 'Event 3', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months' + interval '15 days'),
    (:'event4ID', :'group3ID', :'eventCategory2ID', 'in-person', 'Meetup 2', 'meetup-2', 'Event 4', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '15 days'),
    (:'event5ID', :'group3ID', :'eventCategory1ID', 'in-person', 'Conference 3', 'conference-3', 'Event 5', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '15 days'),
    (:'event6ID', :'group4ID', :'eventCategory2ID', 'in-person', 'Meetup 3', 'meetup-3', 'Event 6', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '15 days'),
    (:'event7ID', :'group1ID', :'eventCategory1ID', 'in-person', 'Conference Draft', 'conference-draft', 'Draft Event', 'UTC', false, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '15 days'),
    (:'event8ID', :'group2ID', :'eventCategory2ID', 'in-person', 'Meetup Canceled', 'meetup-canceled', 'Canceled Event', 'UTC', false, true, false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '15 days');

-- Event attendees (in the same months as the events they attend)
-- event1 (month_10): 3 attendees
-- event2 (month_8): 2 attendees
-- event3 (month_6): 2 attendees
-- event4 (month_4): 1 attendee
-- event5 (month_3): 2 attendees
-- event6 (month_2): 1 attendee
insert into event_attendee (event_id, user_id, created_at) values
    (:'event1ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' + interval '1 day'),
    (:'event1ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' + interval '5 days'),
    (:'event1ID', :'user3ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '10 months' + interval '10 days'),
    (:'event2ID', :'user4ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months' + interval '1 day'),
    (:'event2ID', :'user5ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '8 months' + interval '5 days'),
    (:'event3ID', :'user6ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months' + interval '1 day'),
    (:'event3ID', :'user7ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '6 months' + interval '5 days'),
    (:'event4ID', :'user8ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '4 months' + interval '1 day'),
    (:'event5ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '1 day'),
    (:'event5ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '5 days'),
    (:'event6ID', :'user3ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '1 day');

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
            )
        )
        from months
    ),
    'Should return complete accurate JSON for test community'
);

-- Should return empty stats for unknown community
select is(
    get_community_stats(:'nonExistentCommunityID'::uuid)::jsonb,
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
