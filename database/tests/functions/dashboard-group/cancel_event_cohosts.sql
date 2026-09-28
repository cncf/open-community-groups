-- Tests cancel_event closes pending and approved co-host rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5210000-0000-0000-0000-000000000001'
\set communityID 'e5210000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5210000-0000-0000-0000-000000000003'
\set eventID 'e5210000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5210000-0000-0000-0000-000000000005'
\set groupID 'e5210000-0000-0000-0000-000000000006'
\set pendingGroupID 'e5210000-0000-0000-0000-000000000007'
\set rejectedGroupID 'e5210000-0000-0000-0000-000000000008'
\set userID 'e5210000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'rejectedGroupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('starts_at', current_timestamp + interval '2 days'));

-- Co-host rows covering close and untouched statuses
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'eventID', :'approvedGroupID'),
    (null, 'pending', :'eventID', :'pendingGroupID'),
    (null, 'rejected', :'eventID', :'rejectedGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel the event and close pending and approved co-hosts
select lives_ok(
    format('select cancel_event(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'groupID', :'eventID'),
    'Should cancel the event and close pending and approved co-hosts'
);

-- Should preserve approval evidence and leave rejected rows untouched
select results_eq(
    format($$select group_id, event_cohost_status_id, approved_at is not null from event_cohost where event_id = %L::uuid order by group_id$$, :'eventID'),
    format($$
        values
            (%L::uuid, 'event-canceled', true),
            (%L::uuid, 'event-canceled', false),
            (%L::uuid, 'rejected', false)
    $$, :'approvedGroupID', :'pendingGroupID', :'rejectedGroupID'),
    'Should preserve approval evidence and leave rejected rows untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
