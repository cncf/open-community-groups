-- Tests unpublish_event preserves co-host statuses and approval evidence.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5250000-0000-0000-0000-000000000001'
\set communityID 'e5250000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5250000-0000-0000-0000-000000000003'
\set eventID 'e5250000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5250000-0000-0000-0000-000000000005'
\set groupID 'e5250000-0000-0000-0000-000000000006'
\set userID 'e5250000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, category, groups, published event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true, 'starts_at', current_timestamp + interval '2 days'));

-- Approved co-host row to preserve through unpublish
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id)
values ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'approvedGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should unpublish the event
select lives_ok(
    format('select unpublish_event(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'groupID', :'eventID'),
    'Should unpublish the event'
);

-- Should preserve co-host status and approval evidence
select results_eq(
    format($$select event_cohost_status_id, approved_at from event_cohost where event_id = %L::uuid$$, :'eventID'),
    $$ values ('approved', '2025-01-01 00:00:00+00'::timestamptz) $$,
    'Should preserve co-host status and approval evidence'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
