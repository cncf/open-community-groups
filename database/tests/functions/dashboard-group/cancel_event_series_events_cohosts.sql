-- Tests cancel_event_series_events closes co-host rows for every occurrence.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5230000-0000-0000-0000-000000000001'
\set communityID 'e5230000-0000-0000-0000-000000000002'
\set event1ID 'e5230000-0000-0000-0000-000000000003'
\set event2ID 'e5230000-0000-0000-0000-000000000004'
\set eventCategoryID 'e5230000-0000-0000-0000-000000000005'
\set eventSeriesID 'e5230000-0000-0000-0000-000000000006'
\set groupCategoryID 'e5230000-0000-0000-0000-000000000007'
\set groupID 'e5230000-0000-0000-0000-000000000008'
\set userID 'e5230000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');

-- Series and occurrences
insert into event_series (event_series_id, group_id, recurrence_additional_occurrences, recurrence_anchor_starts_at, recurrence_pattern, timezone)
values (:'eventSeriesID', :'groupID', 1, current_timestamp + interval '4 days', 'weekly', 'UTC');
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '11 days'));

-- Pending co-host rows on both occurrences
insert into event_cohost (event_id, group_id) values
    (:'event1ID', :'cohostGroupID'),
    (:'event2ID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel the series occurrences
select lives_ok(
    format('select cancel_event_series_events(%L::uuid, %L::uuid, array[%L::uuid,%L::uuid])', :'userID', :'groupID', :'event1ID', :'event2ID'),
    'Should cancel the series occurrences'
);

-- Should close co-host rows for every canceled occurrence
select is(
    (select count(*)::int from event_cohost where event_id in (:'event1ID', :'event2ID') and event_cohost_status_id = 'event-canceled'),
    2,
    'Should close co-host rows for every canceled occurrence'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
