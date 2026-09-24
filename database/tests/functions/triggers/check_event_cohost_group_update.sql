-- Tests check_event_cohost_group rejects self co-hosting on updates.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e52b0000-0000-0000-0000-000000000001'
\set communityID 'e52b0000-0000-0000-0000-000000000002'
\set event1ID 'e52b0000-0000-0000-0000-000000000003'
\set event2ID 'e52b0000-0000-0000-0000-000000000004'
\set eventCategoryID 'e52b0000-0000-0000-0000-000000000005'
\set groupCategoryID 'e52b0000-0000-0000-0000-000000000006'
\set groupID 'e52b0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'event1ID', :'groupID', :'eventCategoryID');
select fx_event(:'event2ID', :'cohostGroupID', :'eventCategoryID');

-- Valid co-host row that update scenarios mutate
insert into event_cohost (event_id, group_id)
values (:'event1ID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject updating group_id to the event owner group
select throws_ok(
    format('update event_cohost set group_id = %L::uuid where event_id = %L::uuid', :'groupID', :'event1ID'),
    'event group cannot co-host its own event',
    'Should reject updating group_id to the event owner group'
);

-- Should reject updating event_id to an event owned by the co-host group
select throws_ok(
    format('update event_cohost set event_id = %L::uuid where event_id = %L::uuid and group_id = %L::uuid', :'event2ID', :'event1ID', :'cohostGroupID'),
    'event group cannot co-host its own event',
    'Should reject updating event_id to an event owned by the co-host group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
