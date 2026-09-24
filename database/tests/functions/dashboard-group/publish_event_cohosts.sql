-- Tests publish_event co-host response gate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedEventID 'e51e0000-0000-0000-0000-000000000001'
\set approvedGroupID 'e51e0000-0000-0000-0000-000000000002'
\set communityID 'e51e0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e51e0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e51e0000-0000-0000-0000-000000000005'
\set groupID 'e51e0000-0000-0000-0000-000000000006'
\set inactivePendingEventID 'e51e0000-0000-0000-0000-000000000007'
\set inactivePendingGroupID 'e51e0000-0000-0000-0000-000000000008'
\set pendingEventID 'e51e0000-0000-0000-0000-000000000009'
\set pendingGroupID 'e51e0000-0000-0000-0000-00000000000a'
\set userID 'e51e0000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'inactivePendingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID');
select fx_event(:'approvedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('starts_at', current_timestamp + interval '3 days'));
select fx_event(:'inactivePendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object('starts_at', current_timestamp + interval '3 days'));
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object('starts_at', current_timestamp + interval '3 days'));

-- Co-host rows covering publication gate states
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'approvedEventID', :'approvedGroupID'),
    (null, 'pending', :'inactivePendingEventID', :'inactivePendingGroupID'),
    (null, 'pending', :'pendingEventID', :'pendingGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block publishing with an active pending co-host
select throws_ok(
    format('select publish_event(%L::uuid, %L::uuid, %L::uuid, null)', :'userID', :'groupID', :'pendingEventID'),
    'OCG01',
    'co-hosts must respond before the event can be published',
    'Should block publishing with an active pending co-host'
);

-- Should block publishing with an inactive pending co-host
select throws_ok(
    format('select publish_event(%L::uuid, %L::uuid, %L::uuid, null)', :'userID', :'groupID', :'inactivePendingEventID'),
    'OCG01',
    'co-hosts must respond before the event can be published',
    'Should block publishing with an inactive pending co-host'
);

-- Should publish when all co-hosts responded
select lives_ok(
    format('select publish_event(%L::uuid, %L::uuid, %L::uuid, null)', :'userID', :'groupID', :'approvedEventID'),
    'Should publish when all co-hosts responded'
);

-- Should persist publication after all co-hosts responded
select is((select published from event where event_id = :'approvedEventID'), true, 'Should persist publication after all co-hosts responded');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
