-- Tests loading event co-host notification data.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e50b0000-0000-0000-0000-000000000001'
\set communityID 'e50b0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e50b0000-0000-0000-0000-000000000003'
\set eventID 'e50b0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e50b0000-0000-0000-0000-000000000005'
\set invitationID 'e50b0000-0000-0000-0000-000000000006'
\set ownerGroupID 'e50b0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and event
select fx_community(:'communityID', jsonb_build_object('display_name', 'Notify Community'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Notify Co-host'));
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Notify Owner'));
select fx_event(:'eventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'name', 'Deleted Notification Event',
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Co-host row for a deleted event
insert into event_cohost (
    event_id,
    group_id,
    invitation_id
) values (
    :'eventID',
    :'cohostGroupID',
    :'invitationID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should load notification data for deleted events
select is(
    get_event_cohost_notification_data(format(
        '[{"event_id":"%s","cohost_group_id":"%s"}]',
        :'eventID',
        :'cohostGroupID'
    )::jsonb)::jsonb @> format(
        '[{"event_id":"%s","cohost_group_id":"%s","invitation_id":"%s","status":"pending"}]',
        :'eventID',
        :'cohostGroupID',
        :'invitationID'
    )::jsonb,
    true,
    'Should load notification data for deleted events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
