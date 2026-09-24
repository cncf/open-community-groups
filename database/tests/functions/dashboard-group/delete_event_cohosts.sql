-- Tests delete_event closes open and event-canceled co-host rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5220000-0000-0000-0000-000000000001'
\set communityID 'e5220000-0000-0000-0000-000000000002'
\set eventCanceledGroupID 'e5220000-0000-0000-0000-000000000003'
\set eventCategoryID 'e5220000-0000-0000-0000-000000000004'
\set eventID 'e5220000-0000-0000-0000-000000000005'
\set groupCategoryID 'e5220000-0000-0000-0000-000000000006'
\set groupID 'e5220000-0000-0000-0000-000000000007'
\set pendingGroupID 'e5220000-0000-0000-0000-000000000008'
\set userID 'e5220000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, canceled event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'eventCanceledGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true, 'starts_at', current_timestamp + interval '2 days'));

-- Co-host rows covering delete closures
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'eventID', :'approvedGroupID'),
    (current_timestamp, 'event-canceled', :'eventID', :'eventCanceledGroupID'),
    (null, 'pending', :'eventID', :'pendingGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete the event and close pending, approved and event-canceled co-hosts
select lives_ok(
    format('select delete_event(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'groupID', :'eventID'),
    'Should delete the event and close pending, approved and event-canceled co-hosts'
);

-- Should move closed rows to event-deleted while retaining approval evidence
select results_eq(
    format($$select group_id, event_cohost_status_id, approved_at is not null from event_cohost where event_id = %L::uuid order by group_id$$, :'eventID'),
    format($$
        values
            (%L::uuid, 'event-deleted', true),
            (%L::uuid, 'event-deleted', true),
            (%L::uuid, 'event-deleted', false)
    $$, :'approvedGroupID', :'eventCanceledGroupID', :'pendingGroupID'),
    'Should move closed rows to event-deleted while retaining approval evidence'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
