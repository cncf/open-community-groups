-- Tests delete_event_series_events closes event-canceled rows to event-deleted.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5240000-0000-0000-0000-000000000001'
\set communityID 'e5240000-0000-0000-0000-000000000002'
\set event1ID 'e5240000-0000-0000-0000-000000000003'
\set event2ID 'e5240000-0000-0000-0000-000000000004'
\set eventCategoryID 'e5240000-0000-0000-0000-000000000005'
\set eventSeriesID 'e5240000-0000-0000-0000-000000000006'
\set groupCategoryID 'e5240000-0000-0000-0000-000000000007'
\set groupID 'e5240000-0000-0000-0000-000000000008'
\set userID 'e5240000-0000-0000-0000-000000000009'

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

-- Canceled series and occurrences
insert into event_series (event_series_id, group_id, recurrence_additional_occurrences, recurrence_anchor_starts_at, recurrence_pattern, timezone)
values (:'eventSeriesID', :'groupID', 1, current_timestamp + interval '4 days', 'weekly', 'UTC');
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true, 'event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true, 'event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '11 days'));

-- Event-canceled co-host rows on both occurrences
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'event-canceled', :'event1ID', :'cohostGroupID'),
    (current_timestamp, 'event-canceled', :'event2ID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete the series occurrences
select lives_ok(
    format('select delete_event_series_events(%L::uuid, %L::uuid, array[%L::uuid,%L::uuid])', :'userID', :'groupID', :'event1ID', :'event2ID'),
    'Should delete the series occurrences'
);

-- Should close event-canceled rows to event-deleted while keeping approval evidence
select results_eq(
    format($$select event_cohost_status_id, approved_at is not null from event_cohost where event_id in (%L::uuid, %L::uuid) order by event_id$$, :'event1ID', :'event2ID'),
    $$ values ('event-deleted', true), ('event-deleted', true) $$,
    'Should close event-canceled rows to event-deleted while keeping approval evidence'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
