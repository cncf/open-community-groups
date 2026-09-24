-- Tests unpublish_event_series_events preserves co-host statuses and approval evidence.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5260000-0000-0000-0000-000000000001'
\set communityID 'e5260000-0000-0000-0000-000000000002'
\set event1ID 'e5260000-0000-0000-0000-000000000003'
\set event2ID 'e5260000-0000-0000-0000-000000000004'
\set eventCategoryID 'e5260000-0000-0000-0000-000000000005'
\set eventSeriesID 'e5260000-0000-0000-0000-000000000006'
\set groupCategoryID 'e5260000-0000-0000-0000-000000000007'
\set groupID 'e5260000-0000-0000-0000-000000000008'
\set userID 'e5260000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, category, groups and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');

-- Published series and occurrences
insert into event_series (event_series_id, group_id, recurrence_additional_occurrences, recurrence_anchor_starts_at, recurrence_pattern, timezone)
values (:'eventSeriesID', :'groupID', 1, current_timestamp + interval '4 days', 'weekly', 'UTC');
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'published', true, 'starts_at', current_timestamp + interval '4 days'));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesID', 'published', true, 'starts_at', current_timestamp + interval '11 days'));

-- Approved co-host rows to preserve through series unpublish
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'event1ID', :'cohostGroupID'),
    ('2025-01-02 00:00:00+00', 'approved', :'event2ID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should unpublish all series occurrences
select lives_ok(
    format('select unpublish_event_series_events(%L::uuid, %L::uuid, array[%L::uuid,%L::uuid])', :'userID', :'groupID', :'event1ID', :'event2ID'),
    'Should unpublish all series occurrences'
);

-- Should preserve co-host statuses and approval evidence across series unpublish
select results_eq(
    format($$select event_id, event_cohost_status_id, approved_at is not null from event_cohost where event_id in (%L::uuid, %L::uuid) order by event_id$$, :'event1ID', :'event2ID'),
    format($$ values (%L::uuid, 'approved', true), (%L::uuid, 'approved', true) $$, :'event1ID', :'event2ID'),
    'Should preserve co-host statuses and approval evidence across series unpublish'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
