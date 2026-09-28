-- Tests publish_event_series_events co-host response gate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e51f0000-0000-0000-0000-000000000001'
\set eventCategoryID 'e51f0000-0000-0000-0000-000000000002'
\set eventReadyID 'e51f0000-0000-0000-0000-000000000003'
\set eventPendingID 'e51f0000-0000-0000-0000-000000000004'
\set eventSeriesID 'e51f0000-0000-0000-0000-000000000005'
\set groupCategoryID 'e51f0000-0000-0000-0000-000000000006'
\set groupID 'e51f0000-0000-0000-0000-000000000007'
\set pendingGroupID 'e51f0000-0000-0000-0000-000000000008'
\set userID 'e51f0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, owner group, actor and co-host
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');

-- Event series for publish gate checks
insert into event_series (event_series_id, group_id, recurrence_additional_occurrences, recurrence_anchor_starts_at, recurrence_pattern, timezone)
values (:'eventSeriesID', :'groupID', 1, current_timestamp + interval '4 days', 'weekly', 'UTC');

-- Series events where one occurrence still has a pending co-host
select fx_event(:'eventPendingID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'eventReadyID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '11 days'));

-- Pending co-host on one occurrence blocks the whole series
insert into event_cohost (event_id, group_id) values (:'eventPendingID', :'pendingGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject series publication when one occurrence has a pending co-host
select throws_ok(
    format('select publish_event_series_events(%L::uuid, %L::uuid, array[%L::uuid,%L::uuid], null)', :'userID', :'groupID', :'eventPendingID', :'eventReadyID'),
    'OCG01',
    'co-hosts must respond for every event in the series before publishing',
    'Should reject series publication when one occurrence has a pending co-host'
);

-- Should leave every occurrence unpublished after the rejection
select is(
    (select bool_or(published) from event where event_id in (:'eventPendingID', :'eventReadyID')),
    false,
    'Should leave every occurrence unpublished after the rejection'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
