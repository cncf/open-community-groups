-- Tests the ten-year period boundaries of site statistics.
-- Split from get_site_stats.sql because these scenarios need rows around the
-- ten-year cutoff that would change the base file's exact statistics payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '9a0b0000-0000-0000-0000-000000000001'
\set eventAfterID '9a0b0000-0000-0000-0000-000000000002'
\set eventAtID '9a0b0000-0000-0000-0000-000000000003'
\set eventBeforeID '9a0b0000-0000-0000-0000-000000000004'
\set eventCategoryID '9a0b0000-0000-0000-0000-000000000005'
\set eventFutureID '9a0b0000-0000-0000-0000-000000000006'
\set eventOldID '9a0b0000-0000-0000-0000-000000000007'
\set eventUndatedID '9a0b0000-0000-0000-0000-000000000008'
\set groupAfterID '9a0b0000-0000-0000-0000-000000000009'
\set groupAtID '9a0b0000-0000-0000-0000-00000000000a'
\set groupBeforeID '9a0b0000-0000-0000-0000-00000000000b'
\set groupCategoryID '9a0b0000-0000-0000-0000-00000000000c'
\set groupOldID '9a0b0000-0000-0000-0000-00000000000d'
\set user1ID '9a0b0000-0000-0000-0000-00000000000e'
\set user2ID '9a0b0000-0000-0000-0000-00000000000f'
\set user3ID '9a0b0000-0000-0000-0000-000000000010'
\set user4ID '9a0b0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community
select fx_community(:'communityID');

-- User joining and attending one second before the cutoff
select fx_user(:'user1ID');

-- User joining and attending exactly at the cutoff
select fx_user(:'user2ID');

-- User joining and attending one second after the cutoff
select fx_user(:'user3ID');

-- User joining a group before the period
select fx_user(:'user4ID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group created one second after the cutoff
select fx_group(:'groupAfterID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', (current_date - interval '10 years')::timestamptz + interval '1 second'
));

-- Group created exactly at the cutoff
select fx_group(:'groupAtID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', (current_date - interval '10 years')::timestamptz
));

-- Group created one second before the cutoff
select fx_group(:'groupBeforeID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', (current_date - interval '10 years')::timestamptz - interval '1 second'
));

-- Group created two years before the period
select fx_group(:'groupOldID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', (current_date - interval '12 years')::timestamptz
));

-- Event starting one second after the cutoff
select fx_event(:'eventAfterID', :'groupAtID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (current_date - interval '10 years')::timestamptz + interval '1 second'
));

-- Event starting exactly at the cutoff
select fx_event(:'eventAtID', :'groupAtID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (current_date - interval '10 years')::timestamptz
));

-- Event starting one second before the cutoff
select fx_event(:'eventBeforeID', :'groupAtID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (current_date - interval '10 years')::timestamptz - interval '1 second'
));

-- Event starting in the future
select fx_event(:'eventFutureID', :'groupAtID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '2 months'
));

-- Event starting two years before the period
select fx_event(:'eventOldID', :'groupAtID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (current_date - interval '12 years')::timestamptz
));

-- Published event without a start date
select fx_event(:'eventUndatedID', :'groupAtID', :'eventCategoryID', jsonb_build_object(
    'published', true
));

-- Group members joining around the cutoff and before the period
insert into group_member (group_id, user_id, created_at)
values
    (:'groupAtID', :'user1ID', (current_date - interval '10 years')::timestamptz - interval '1 second'),
    (:'groupAtID', :'user2ID', (current_date - interval '10 years')::timestamptz),
    (:'groupAtID', :'user3ID', (current_date - interval '10 years')::timestamptz + interval '1 second'),
    (:'groupOldID', :'user4ID', (current_date - interval '12 years')::timestamptz);

-- Confirmed attendees around the cutoff, of an undated event and before the period
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'eventAtID', :'user1ID', 'confirmed', (current_date - interval '10 years')::timestamptz - interval '1 second'),
    (:'eventAtID', :'user2ID', 'confirmed', (current_date - interval '10 years')::timestamptz),
    (:'eventAtID', :'user3ID', 'confirmed', (current_date - interval '10 years')::timestamptz + interval '1 second'),
    (:'eventUndatedID', :'user1ID', 'confirmed', date_trunc('month', current_timestamp) - interval '1 month' + interval '1 day'),
    (:'eventOldID', :'user4ID', 'confirmed', (current_date - interval '12 years')::timestamptz);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count rows older than the period in totals only
select is(
    (
        select jsonb_build_object(
            'attendees', stats->'attendees'->'total',
            'events', stats->'events'->'total',
            'groups', stats->'groups'->'total',
            'members', stats->'members'->'total'
        )
        from (select get_site_stats()::jsonb as stats) site_stats
    ),
    '{"attendees": 5, "events": 6, "groups": 4, "members": 4}'::jsonb,
    'Should count rows older than the period in totals only'
);

-- Should count undated events in totals only and their attendees in attendee series
select is(
    (
        select jsonb_build_object(
            'attendees_per_month', stats->'attendees'->'per_month'->1,
            'events_per_month', stats->'events'->'per_month'
        )
        from (select get_site_stats()::jsonb as stats) site_stats
    ),
    (
        with buckets as (
            select
                timezone('UTC', date_trunc(
                    'month',
                    (current_date - interval '10 years')::timestamptz at time zone 'UTC'
                )) as cutoff_month,
                timezone('UTC', date_trunc(
                    'month',
                    (current_timestamp + interval '2 months') at time zone 'UTC'
                )) as future_month,
                timezone('UTC', date_trunc(
                    'month',
                    (date_trunc('month', current_timestamp) - interval '1 month' + interval '1 day') at time zone 'UTC'
                )) as recent_month
        )
        select jsonb_build_object(
            'attendees_per_month', jsonb_build_array(to_char(recent_month, 'YYYY-MM'), 1),
            'events_per_month', jsonb_build_array(
                jsonb_build_array(to_char(cutoff_month, 'YYYY-MM'), 2),
                jsonb_build_array(to_char(future_month, 'YYYY-MM'), 1)
            )
        )
        from buckets
    ),
    'Should count undated events in totals only and their attendees in attendee series'
);

-- Should include future-dated rows
select is(
    get_site_stats()::jsonb->'events'->'running_total'->1,
    (
        select jsonb_build_array(
            floor(extract(epoch from timezone('UTC', date_trunc(
                'month',
                (current_timestamp + interval '2 months') at time zone 'UTC'
            ))) * 1000)::bigint,
            3
        )
    ),
    'Should include future-dated rows'
);

-- Should split the boundary month at the exact ten-year cutoff
select is(
    (
        select jsonb_build_object(
            'attendees', stats->'attendees'->'per_month'->0,
            'events', stats->'events'->'per_month'->0,
            'groups', stats->'groups'->'per_month',
            'members', stats->'members'->'per_month'
        )
        from (select get_site_stats()::jsonb as stats) site_stats
    ),
    (
        with buckets as (
            select to_char(
                timezone('UTC', date_trunc(
                    'month',
                    (current_date - interval '10 years')::timestamptz at time zone 'UTC'
                )),
                'YYYY-MM'
            ) as cutoff_label
        )
        select jsonb_build_object(
            'attendees', jsonb_build_array(cutoff_label, 2),
            'events', jsonb_build_array(cutoff_label, 2),
            'groups', jsonb_build_array(jsonb_build_array(cutoff_label, 2)),
            'members', jsonb_build_array(jsonb_build_array(cutoff_label, 2))
        )
        from buckets
    ),
    'Should split the boundary month at the exact ten-year cutoff'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
