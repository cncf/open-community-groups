-- Tests loading event co-host notification data.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostCommunityID 'e50b0000-0000-0000-0000-000000000001'
\set cohostGroupCategoryID 'e50b0000-0000-0000-0000-000000000002'
\set cohostGroupID 'e50b0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e50b0000-0000-0000-0000-000000000004'
\set eventID 'e50b0000-0000-0000-0000-000000000005'
\set invitationID 'e50b0000-0000-0000-0000-000000000006'
\set ownerCommunityID 'e50b0000-0000-0000-0000-000000000007'
\set ownerGroupCategoryID 'e50b0000-0000-0000-0000-000000000008'
\set ownerGroupID 'e50b0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Co-host group in its own community
select fx_community(:'cohostCommunityID', jsonb_build_object('display_name', 'Notify Co-host Community'));
select fx_group_category(:'cohostGroupCategoryID', :'cohostCommunityID');
select fx_group(:'cohostGroupID', :'cohostCommunityID', :'cohostGroupCategoryID', jsonb_build_object('name', 'Notify Co-host'));

-- Owner community, group and event
select fx_community(:'ownerCommunityID', jsonb_build_object('display_name', 'Notify Community'));
select fx_event_category(:'eventCategoryID', :'ownerCommunityID');
select fx_group_category(:'ownerGroupCategoryID', :'ownerCommunityID');
select fx_group(:'ownerGroupID', :'ownerCommunityID', :'ownerGroupCategoryID', jsonb_build_object('name', 'Notify Owner'));
select fx_event(:'eventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'deleted', true,
    'name', 'Deleted Notification Event',
    'starts_at', '2099-01-01 10:00:00+00',
    'timezone', 'Europe/Madrid'
));

-- Pending co-host row for a canceled and deleted event
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id,
    invitation_id
) values (
    'pending',
    :'eventID',
    :'cohostGroupID',
    :'invitationID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should load the full notification payload for deleted events
select is(
    get_event_cohost_notification_data(jsonb_build_array(
        jsonb_build_object('cohost_group_id', :'cohostGroupID', 'event_id', :'eventID')
    ))::jsonb,
    jsonb_build_array(jsonb_build_object(
        'canceled', true,
        'cohost_community_display_name', 'Notify Co-host Community',
        'cohost_group_id', :'cohostGroupID'::uuid,
        'cohost_group_name', 'Notify Co-host',
        'event_id', :'eventID'::uuid,
        'event_name', 'Deleted Notification Event',
        'invitation_id', :'invitationID'::uuid,
        'owner_community_display_name', 'Notify Community',
        'owner_community_id', :'ownerCommunityID'::uuid,
        'owner_group_id', :'ownerGroupID'::uuid,
        'owner_group_name', 'Notify Owner',
        'status', 'pending',
        'timezone', 'Europe/Madrid',

        'starts_at', 4070944800
    )),
    'Should load the full notification payload for deleted events'
);

-- Should return an empty array for null items
select is(
    get_event_cohost_notification_data(null)::jsonb,
    '[]'::jsonb,
    'Should return an empty array for null items'
);

-- Should return one payload for duplicate items
select is(
    (
        select jsonb_agg(item->>'invitation_id')
        from jsonb_array_elements(
            get_event_cohost_notification_data(jsonb_build_array(
                jsonb_build_object('cohost_group_id', :'cohostGroupID', 'event_id', :'eventID'),
                jsonb_build_object('cohost_group_id', :'cohostGroupID', 'event_id', :'eventID')
            ))::jsonb
        ) item
    ),
    jsonb_build_array(:'invitationID'),
    'Should return one payload for duplicate items'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
