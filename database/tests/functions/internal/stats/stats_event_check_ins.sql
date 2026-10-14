-- Tests check-in arrival bins of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea080000-0000-0000-0000-000000000001'
\set eventCategoryID 'ea080000-0000-0000-0000-000000000002'
\set eventCutoffHourlyID 'ea080000-0000-0000-0000-000000000003'
\set eventCutoffQuarterID 'ea080000-0000-0000-0000-000000000004'
\set eventEmptyID 'ea080000-0000-0000-0000-000000000005'
\set eventMultiDayID 'ea080000-0000-0000-0000-000000000006'
\set eventOutsideID 'ea080000-0000-0000-0000-000000000007'
\set eventQuarterID 'ea080000-0000-0000-0000-000000000008'
\set eventUndatedID 'ea080000-0000-0000-0000-000000000009'
\set groupCategoryID 'ea080000-0000-0000-0000-00000000000a'
\set groupID 'ea080000-0000-0000-0000-00000000000b'
\set user1ID 'ea080000-0000-0000-0000-00000000000c'
\set user2ID 'ea080000-0000-0000-0000-00000000000d'
\set user3ID 'ea080000-0000-0000-0000-00000000000e'
\set user4ID 'ea080000-0000-0000-0000-00000000000f'
\set user5ID 'ea080000-0000-0000-0000-000000000010'
\set user6ID 'ea080000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');
select fx_user(:'user5ID');
select fx_user(:'user6ID');

-- Multi-day event with check-ins around both six-hour cutoffs
select fx_event(:'eventCutoffHourlyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-07-04 09:30:00+00',
    'starts_at', '2030-07-01 09:30:00+00'
));

-- Event starting off the quarter hour with check-ins around both six-hour cutoffs
select fx_event(:'eventCutoffQuarterID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-06-01 11:07:00+00',
    'starts_at', '2030-06-01 10:07:00+00'
));

-- Event without check-ins
select fx_event(:'eventEmptyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-05-01 12:00:00+00',
    'starts_at', '2030-05-01 10:00:00+00'
));

-- Multi-day event with check-ins spanning more than three days
select fx_event(:'eventMultiDayID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-03-05 18:00:00+00',
    'starts_at', '2030-03-01 09:00:00+00'
));

-- Event with check-ins before and after its bounded span
select fx_event(:'eventOutsideID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-02-01 11:00:00+00',
    'starts_at', '2030-02-01 10:00:00+00'
));

-- Event starting off the quarter hour
select fx_event(:'eventQuarterID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-01 12:00:00+00',
    'starts_at', '2030-01-01 10:20:00+00'
));

-- Event without dates
select fx_event(:'eventUndatedID', :'groupID', :'eventCategoryID');

-- Check-ins, plus confirmed attendees not checked in and canceled checked-in attendees
insert into event_attendee (event_id, user_id, checked_in, status, attendance_canceled_at, checked_in_at) values
    (:'eventCutoffHourlyID', :'user1ID', true, 'confirmed', null, '2030-07-01 03:10:00+00'),
    (:'eventCutoffHourlyID', :'user2ID', true, 'confirmed', null, '2030-07-01 03:40:00+00'),
    (:'eventCutoffHourlyID', :'user3ID', true, 'confirmed', null, '2030-07-04 15:30:00+00'),
    (:'eventCutoffHourlyID', :'user4ID', true, 'confirmed', null, '2030-07-04 15:50:00+00'),
    (:'eventCutoffQuarterID', :'user1ID', true, 'confirmed', null, '2030-06-01 04:03:00+00'),
    (:'eventCutoffQuarterID', :'user2ID', true, 'confirmed', null, '2030-06-01 04:07:00+00'),
    (:'eventCutoffQuarterID', :'user3ID', true, 'confirmed', null, '2030-06-01 17:07:00+00'),
    (:'eventCutoffQuarterID', :'user4ID', true, 'confirmed', null, '2030-06-01 17:10:00+00'),
    (:'eventEmptyID', :'user1ID', false, 'confirmed', null, null),
    (:'eventMultiDayID', :'user1ID', true, 'confirmed', null, '2030-03-01 08:30:00+00'),
    (:'eventMultiDayID', :'user2ID', true, 'confirmed', null, '2030-03-04 09:10:00+00'),
    (:'eventOutsideID', :'user1ID', true, 'confirmed', null, '2030-01-31 20:00:00+00'),
    (:'eventOutsideID', :'user2ID', true, 'confirmed', null, '2030-02-01 09:55:00+00'),
    (:'eventOutsideID', :'user3ID', true, 'confirmed', null, '2030-02-01 18:30:00+00'),
    (:'eventQuarterID', :'user1ID', true, 'confirmed', null, '2030-01-01 09:35:00+00'),
    (:'eventQuarterID', :'user2ID', true, 'confirmed', null, '2030-01-01 09:50:00+00'),
    (:'eventQuarterID', :'user3ID', true, 'confirmed', null, '2030-01-01 10:05:00+00'),
    (:'eventQuarterID', :'user4ID', true, 'confirmed', null, '2030-01-01 10:29:00+00'),
    (:'eventQuarterID', :'user5ID', false, 'confirmed', null, null),
    (:'eventQuarterID', :'user6ID', true, 'attendance-canceled', '2030-01-01 11:00:00+00', '2030-01-01 10:10:00+00'),
    (:'eventUndatedID', :'user1ID', true, 'confirmed', null, '2030-04-01 14:07:00+00'),
    (:'eventUndatedID', :'user2ID', true, 'confirmed', null, '2030-04-01 14:52:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should align bins to the hour of the first check-in for undated events
select is(
    (select stats_event_check_ins(e)::jsonb from event e where e.event_id = :'eventUndatedID'),
    jsonb_build_object(
        'bin_minutes', 15,
        'bins', jsonb_build_array(
            jsonb_build_array(floor(extract(epoch from '2030-04-01 14:00:00+00'::timestamptz) * 1000)::bigint, 1),
            jsonb_build_array(floor(extract(epoch from '2030-04-01 14:15:00+00'::timestamptz) * 1000)::bigint, 0),
            jsonb_build_array(floor(extract(epoch from '2030-04-01 14:30:00+00'::timestamptz) * 1000)::bigint, 0),
            jsonb_build_array(floor(extract(epoch from '2030-04-01 14:45:00+00'::timestamptz) * 1000)::bigint, 1)
        ),
        'outside_range', 0
    ),
    'Should align bins to the hour of the first check-in for undated events'
);

-- Should align quarter-hour bins to the hour of the event start
select is(
    (select stats_event_check_ins(e)::jsonb from event e where e.event_id = :'eventQuarterID'),
    jsonb_build_object(
        'bin_minutes', 15,
        'bins', jsonb_build_array(
            jsonb_build_array(floor(extract(epoch from '2030-01-01 09:15:00+00'::timestamptz) * 1000)::bigint, 0),
            jsonb_build_array(floor(extract(epoch from '2030-01-01 09:30:00+00'::timestamptz) * 1000)::bigint, 1),
            jsonb_build_array(floor(extract(epoch from '2030-01-01 09:45:00+00'::timestamptz) * 1000)::bigint, 1),
            jsonb_build_array(floor(extract(epoch from '2030-01-01 10:00:00+00'::timestamptz) * 1000)::bigint, 1),
            jsonb_build_array(floor(extract(epoch from '2030-01-01 10:15:00+00'::timestamptz) * 1000)::bigint, 1)
        ),
        'outside_range', 0
    ),
    'Should align quarter-hour bins to the hour of the event start'
);

-- Should count check-ins outside the bounded span separately
select is(
    (
        select jsonb_build_object(
            'bins', jsonb_array_length(check_ins->'bins'),
            'first_bin', check_ins->'bins'->0->0,
            'last_bin', check_ins->'bins'->-1->0,
            'outside_range', check_ins->'outside_range'
        )
        from (
            select stats_event_check_ins(e)::jsonb as check_ins
            from event e
            where e.event_id = :'eventOutsideID'
        ) stats
    ),
    jsonb_build_object(
        'bins', 53,
        'first_bin', floor(extract(epoch from '2030-02-01 04:00:00+00'::timestamptz) * 1000)::bigint,
        'last_bin', floor(extract(epoch from '2030-02-01 17:00:00+00'::timestamptz) * 1000)::bigint,
        'outside_range', 2
    ),
    'Should count check-ins outside the bounded span separately'
);

-- Should exclude check-ins just past the six-hour cutoffs from hourly bins
select is(
    (
        select jsonb_build_object(
            'bin_minutes', check_ins->'bin_minutes',
            'bins', jsonb_array_length(check_ins->'bins'),
            'first_bin', check_ins->'bins'->0,
            'last_bin', check_ins->'bins'->-1,
            'outside_range', check_ins->'outside_range'
        )
        from (
            select stats_event_check_ins(e)::jsonb as check_ins
            from event e
            where e.event_id = :'eventCutoffHourlyID'
        ) stats
    ),
    jsonb_build_object(
        'bin_minutes', 60,
        'bins', 85,
        'first_bin', jsonb_build_array(floor(extract(epoch from '2030-07-01 03:00:00+00'::timestamptz) * 1000)::bigint, 1),
        'last_bin', jsonb_build_array(floor(extract(epoch from '2030-07-04 15:00:00+00'::timestamptz) * 1000)::bigint, 1),
        'outside_range', 2
    ),
    'Should exclude check-ins just past the six-hour cutoffs from hourly bins'
);

-- Should exclude check-ins just past the six-hour cutoffs from quarter-hour bins
select is(
    (
        select jsonb_build_object(
            'bin_minutes', check_ins->'bin_minutes',
            'bins', jsonb_array_length(check_ins->'bins'),
            'first_bin', check_ins->'bins'->0,
            'last_bin', check_ins->'bins'->-1,
            'outside_range', check_ins->'outside_range'
        )
        from (
            select stats_event_check_ins(e)::jsonb as check_ins
            from event e
            where e.event_id = :'eventCutoffQuarterID'
        ) stats
    ),
    jsonb_build_object(
        'bin_minutes', 15,
        'bins', 53,
        'first_bin', jsonb_build_array(floor(extract(epoch from '2030-06-01 04:00:00+00'::timestamptz) * 1000)::bigint, 1),
        'last_bin', jsonb_build_array(floor(extract(epoch from '2030-06-01 17:00:00+00'::timestamptz) * 1000)::bigint, 1),
        'outside_range', 2
    ),
    'Should exclude check-ins just past the six-hour cutoffs from quarter-hour bins'
);

-- Should return empty bins for events without check-ins
select is(
    (select stats_event_check_ins(e)::jsonb from event e where e.event_id = :'eventEmptyID'),
    '{"bin_minutes": 15, "bins": [], "outside_range": 0}'::jsonb,
    'Should return empty bins for events without check-ins'
);

-- Should switch to hourly bins when the span exceeds three days
select is(
    (
        select jsonb_build_object(
            'bin_minutes', check_ins->'bin_minutes',
            'bins', jsonb_array_length(check_ins->'bins'),
            'first_bin', check_ins->'bins'->0,
            'last_bin', check_ins->'bins'->-1
        )
        from (
            select stats_event_check_ins(e)::jsonb as check_ins
            from event e
            where e.event_id = :'eventMultiDayID'
        ) stats
    ),
    jsonb_build_object(
        'bin_minutes', 60,
        'bins', 74,
        'first_bin', jsonb_build_array(floor(extract(epoch from '2030-03-01 08:00:00+00'::timestamptz) * 1000)::bigint, 1),
        'last_bin', jsonb_build_array(floor(extract(epoch from '2030-03-04 09:00:00+00'::timestamptz) * 1000)::bigint, 1)
    ),
    'Should switch to hourly bins when the span exceeds three days'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
