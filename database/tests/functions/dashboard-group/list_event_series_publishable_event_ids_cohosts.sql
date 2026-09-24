-- Tests list_event_series_publishable_event_ids keeps pending co-host occurrences candidate publish targets.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5200000-0000-0000-0000-000000000001'
\set communityID 'e5200000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5200000-0000-0000-0000-000000000003'
\set eventPendingID 'e5200000-0000-0000-0000-000000000004'
\set eventReadyID 'e5200000-0000-0000-0000-000000000005'
\set eventSeriesID 'e5200000-0000-0000-0000-000000000006'
\set groupCategoryID 'e5200000-0000-0000-0000-000000000007'
\set groupID 'e5200000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, owner and co-host groups
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event series
insert into event_series (event_series_id, group_id, recurrence_additional_occurrences, recurrence_anchor_starts_at, recurrence_pattern, timezone)
values (:'eventSeriesID', :'groupID', 1, current_timestamp + interval '4 days', 'weekly', 'UTC');

-- Unpublished series occurrences
select fx_event(:'eventPendingID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'eventReadyID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'starts_at', current_timestamp + interval '11 days'));

-- Pending co-host row should not affect candidate discovery
insert into event_cohost (event_id, group_id) values (:'eventPendingID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep pending co-host occurrences in the publishable candidate list
select is(
    list_event_series_publishable_event_ids(:'groupID'::uuid, :'eventPendingID'::uuid),
    array[:'eventPendingID'::uuid, :'eventReadyID'::uuid],
    'Should keep pending co-host occurrences in the publishable candidate list'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
