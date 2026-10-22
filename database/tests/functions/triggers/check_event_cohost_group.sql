-- Tests rejecting event groups as their own co-host on inserts and updates.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedEventID 'e5100000-0000-0000-0000-000000000006'
\set cohostGroupEventID 'e5100000-0000-0000-0000-000000000007'
\set cohostGroupID 'e5100000-0000-0000-0000-000000000008'
\set communityID 'e5100000-0000-0000-0000-000000000001'
\set eventCategoryID 'e5100000-0000-0000-0000-000000000002'
\set eventID 'e5100000-0000-0000-0000-000000000003'
\set groupCategoryID 'e5100000-0000-0000-0000-000000000004'
\set groupID 'e5100000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'acceptedEventID', :'groupID', :'eventCategoryID');
select fx_event(:'cohostGroupEventID', :'cohostGroupID', :'eventCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Valid co-host row that the update scenarios try to repoint
insert into event_cohost (event_id, group_id)
values (:'eventID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a co-host group other than the event group
select lives_ok(
    format(
        'insert into event_cohost (event_id, group_id) values (%L::uuid, %L::uuid)',
        :'acceptedEventID',
        :'cohostGroupID'
    ),
    'Should accept a co-host group other than the event group'
);

-- Should reject a group co-hosting its own event
select throws_ok(
    format(
        'insert into event_cohost (event_id, group_id) values (%L::uuid, %L::uuid)',
        :'eventID',
        :'groupID'
    ),
    'P0001',
    'event group cannot co-host its own event',
    'Should reject a group co-hosting its own event'
);

-- Should reject updating event_id to an event owned by the co-host group
select throws_ok(
    format(
        'update event_cohost set event_id = %L::uuid where event_id = %L::uuid and group_id = %L::uuid',
        :'cohostGroupEventID',
        :'eventID',
        :'cohostGroupID'
    ),
    'P0001',
    'event group cannot co-host its own event',
    'Should reject updating event_id to an event owned by the co-host group'
);

-- Should reject updating group_id to the event owner group
select throws_ok(
    format(
        'update event_cohost set group_id = %L::uuid where event_id = %L::uuid and group_id = %L::uuid',
        :'groupID',
        :'eventID',
        :'cohostGroupID'
    ),
    'P0001',
    'event group cannot co-host its own event',
    'Should reject updating group_id to the event owner group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
