-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000301'
\set event2ID '00000000-0000-0000-0000-000000000302'
\set event3ID '00000000-0000-0000-0000-000000000303'
\set eventCategory2ID '00000000-0000-0000-0000-000000000202'
\set eventCategoryID '00000000-0000-0000-0000-000000000201'
\set group1ID '00000000-0000-0000-0000-000000000101'
\set group2ID '00000000-0000-0000-0000-000000000102'
\set group3ID '00000000-0000-0000-0000-000000000103'
\set groupCategory2ID '00000000-0000-0000-0000-000000000502'
\set groupCategoryID '00000000-0000-0000-0000-000000000501'
\set nonExistentGroupID '00000000-0000-0000-0000-999999999999'
\set user1ID '00000000-0000-0000-0000-000000000401'
\set user2ID '00000000-0000-0000-0000-000000000402'
\set user3ID '00000000-0000-0000-0000-000000000403'
\set user4ID '00000000-0000-0000-0000-000000000404'

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
    (:'communityID', 'test-community', 'Test Community', 'Community used for group stats tests', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'other-community', 'Other Community', 'Separate community for isolation testing', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech'),
    (:'groupCategory2ID', :'community2ID', 'Tech2');

-- Event categories
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Conference'),
    (:'eventCategory2ID', :'community2ID', 'Conference2');

-- Groups (using relative dates within 2-year window)
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
    (:'group2ID', :'communityID', :'groupCategoryID', 'Group Two', 'group-two',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months', true, false),
    (:'group3ID', :'community2ID', :'groupCategory2ID', 'Other Community Group', 'other-group',
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months', true, false);

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', 'hash-2', 'user2@example.com', 'user2'),
    (:'user3ID', 'hash-3', 'user3@example.com', 'user3'),
    (:'user4ID', 'hash-4', 'user4@example.com', 'user4');

-- Members (month -3 and month -1 relative to current date)
insert into group_member (group_id, user_id, created_at) values
    (:'group1ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' + interval '5 days'),
    (:'group1ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '10 days'),
    (:'group2ID', :'user3ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '15 days');

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
    (:'event1ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event One', 'event-one',
        'First event', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '15 days'),
    (:'event2ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event Two', 'event-two',
        'Second event', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '15 days'),
    (:'event3ID', :'group3ID', :'eventCategory2ID', 'in-person', 'Other Group Event', 'other-event',
        'Other group event', 'UTC', true, false, false,
        date_trunc('month', current_timestamp at time zone 'UTC') + interval '20 days');

-- Attendees (matching event months)
insert into event_attendee (event_id, user_id, created_at) values
    (:'event1ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '1 day'),
    (:'event1ID', :'user2ID', date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '5 days'),
    (:'event2ID', :'user1ID', date_trunc('month', current_timestamp at time zone 'UTC') + interval '10 days'),
    (:'event3ID', :'user4ID', date_trunc('month', current_timestamp at time zone 'UTC') + interval '20 days');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete accurate JSON for seeded group
select is(
    get_group_stats(:'communityID'::uuid, :'group1ID'::uuid)::jsonb,
    (
        with
        -- Define the months used in test data relative to current_timestamp at UTC
        months as (
            select
                date_trunc('month', current_timestamp at time zone 'UTC') as m0,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' as m2,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '3 months' as m3
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
                'total', 2,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m2 at time zone 'UTC') * 1000)::bigint,
                        1
                    ),
                    jsonb_build_array(
                        (extract(epoch from m0 at time zone 'UTC') * 1000)::bigint,
                        2
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 1),
                    jsonb_build_array(to_char(m0, 'YYYY-MM'), 1)
                )
            ),
            'attendees', jsonb_build_object(
                'total', 3,
                'running_total', jsonb_build_array(
                    jsonb_build_array(
                        (extract(epoch from m2 at time zone 'UTC') * 1000)::bigint,
                        2
                    ),
                    jsonb_build_array(
                        (extract(epoch from m0 at time zone 'UTC') * 1000)::bigint,
                        3
                    )
                ),
                'per_month', jsonb_build_array(
                    jsonb_build_array(to_char(m2, 'YYYY-MM'), 2),
                    jsonb_build_array(to_char(m0, 'YYYY-MM'), 1)
                )
            )
        )
        from months
    ),
    'Should return complete accurate JSON for seeded group'
);

-- Should return empty stats for unknown group
select is(
    get_group_stats(:'communityID'::uuid, :'nonExistentGroupID'::uuid)::jsonb,
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
        }
    }
    $$,
    'Should return empty stats for unknown group'
);

-- Should only count events from the requested group
select is(
    (get_group_stats(:'communityID'::uuid, :'group1ID'::uuid)::jsonb->'events'->>'total')::int,
    2,
    'Should only count events from the requested group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
