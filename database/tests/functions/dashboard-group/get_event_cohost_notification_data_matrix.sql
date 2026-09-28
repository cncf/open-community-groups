-- Tests get_event_cohost_notification_data payload shape including deleted events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e51a0000-0000-0000-0000-000000000001'
\set communityID 'e51a0000-0000-0000-0000-000000000002'
\set deletedEventID 'e51a0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e51a0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e51a0000-0000-0000-0000-000000000005'
\set invitationID 'e51a0000-0000-0000-0000-000000000006'
\set ownerGroupID 'e51a0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and deleted event
select fx_community(:'communityID', jsonb_build_object('display_name', 'Notification Matrix'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Notification Co-host'));
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Notification Owner'));
select fx_event(:'deletedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('deleted', true, 'name', 'Deleted Notify', 'starts_at', '2099-01-01 10:00:00+00'));

-- Co-host row for deleted event notification data
insert into event_cohost (event_id, group_id, invitation_id)
values (:'deletedEventID', :'cohostGroupID', :'invitationID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return notification data for deleted events
select ok(
    get_event_cohost_notification_data(format('[{"event_id":"%s","cohost_group_id":"%s"}]', :'deletedEventID', :'cohostGroupID')::jsonb)::jsonb
        @> format('[{"event_id":"%s","cohost_group_id":"%s","invitation_id":"%s","event_name":"Deleted Notify","status":"pending"}]', :'deletedEventID', :'cohostGroupID', :'invitationID')::jsonb,
    'Should return notification data for deleted events'
);

-- Should encode starts_at as epoch seconds and include owner ids
select ok(
    (get_event_cohost_notification_data(format('[{"event_id":"%s","cohost_group_id":"%s"}]', :'deletedEventID', :'cohostGroupID')::jsonb)::jsonb->0)
        @> format('{"starts_at":4070944800,"owner_group_id":"%s","owner_community_id":"%s"}', :'ownerGroupID', :'communityID')::jsonb,
    'Should encode starts_at as epoch seconds and include owner ids'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
