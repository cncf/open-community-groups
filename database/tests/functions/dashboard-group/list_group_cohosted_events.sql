-- Tests listing co-hosted events for a group dashboard with statuses, ordering, and pagination.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e50a0000-0000-0000-0000-000000000001'
\set communityID 'e50a0000-0000-0000-0000-000000000002'
\set deletedEventID 'e50a0000-0000-0000-0000-000000000003'
\set eventApprovedID 'e50a0000-0000-0000-0000-000000000004'
\set eventApprovedInvitationID 'e50a0000-0000-0000-0000-000000000005'
\set eventCanceledID 'e50a0000-0000-0000-0000-000000000006'
\set eventCategoryID 'e50a0000-0000-0000-0000-000000000007'
\set eventDeletedStatusID 'e50a0000-0000-0000-0000-000000000008'
\set eventPendingID 'e50a0000-0000-0000-0000-000000000009'
\set eventRejectedID 'e50a0000-0000-0000-0000-00000000000a'
\set eventRemovedID 'e50a0000-0000-0000-0000-00000000000b'
\set groupCategoryID 'e50a0000-0000-0000-0000-00000000000c'
\set ownerGroupID 'e50a0000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID', jsonb_build_object('display_name', 'Hosted Community', 'name', 'hosted-community'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Owner Events Group', 'slug_pretty', 'owner-pretty'));
select fx_event(:'deletedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('deleted', true, 'starts_at', '2099-01-10 10:00:00+00'));
select fx_event(:'eventApprovedID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('name', 'Approved Event', 'starts_at', '2099-01-06 10:00:00+00'));
select fx_event(:'eventCanceledID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('name', 'Canceled Event', 'starts_at', '2099-01-05 10:00:00+00'));
select fx_event(:'eventDeletedStatusID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('name', 'Event Deleted Status Event', 'starts_at', '2099-01-04 10:00:00+00'));
select fx_event(:'eventPendingID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('name', 'Pending Event', 'starts_at', '2099-01-07 10:00:00+00'));
select fx_event(:'eventRejectedID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('name', 'Rejected Event', 'starts_at', '2099-01-03 10:00:00+00'));
select fx_event(:'eventRemovedID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object('name', 'Removed Event', 'starts_at', '2099-01-02 10:00:00+00'));

-- Approved co-host row on a deleted event, excluded from the list
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invited_at, responded_at)
values (current_timestamp, 'approved', :'deletedEventID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-02 00:00:00+00');

-- Approved co-host row with a known invitation id
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id, invited_at, responded_at)
values (current_timestamp, 'approved', :'eventApprovedID', :'cohostGroupID', :'eventApprovedInvitationID', '2025-01-01 00:00:00+00', '2025-01-02 00:00:00+00');

-- Canceled co-host row
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invited_at, responded_at)
values (current_timestamp, 'canceled', :'eventCanceledID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-03 00:00:00+00');

-- Co-host row closed because its event was deleted
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invited_at, responded_at)
values (current_timestamp, 'event-deleted', :'eventDeletedStatusID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-04 00:00:00+00');

-- Pending co-host row
insert into event_cohost (event_cohost_status_id, event_id, group_id, invited_at)
values ('pending', :'eventPendingID', :'cohostGroupID', '2025-01-01 00:00:00+00');

-- Rejected co-host row
insert into event_cohost (event_cohost_status_id, event_id, group_id, invited_at, responded_at)
values ('rejected', :'eventRejectedID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-05 00:00:00+00');

-- Removed co-host row
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invited_at, responded_at)
values (current_timestamp, 'removed', :'eventRemovedID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-06 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include every co-host status except deleted events
select is(
    (
        select jsonb_agg(item->>'status' order by item->>'status')
        from jsonb_array_elements(list_group_cohosted_events(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb->'events') item
    ),
    '["approved","canceled","event-deleted","pending","rejected","removed"]'::jsonb,
    'Should include every co-host status except deleted events'
);

-- Should include optional and timestamp fields without sensitive internals
select ok(
    (list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":1}'::jsonb)::jsonb->'events'->0)
        ?& array['event_id', 'event_kind', 'event_logo_url', 'invitation_id', 'invited_at', 'owner_group_slug_pretty', 'starts_at', 'timezone']
    and not ((list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":1}'::jsonb)::jsonb->'events'->0) ? 'meeting_join_url'),
    'Should include optional and timestamp fields without sensitive internals'
);

-- Should order non-deleted events by start date descending
select is(
    (
        select array_agg((item->>'event_id')::uuid order by ordinality)
        from jsonb_array_elements(list_group_cohosted_events(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb->'events')
            with ordinality as events(item, ordinality)
    ),
    array[
        :'eventPendingID'::uuid,
        :'eventApprovedID'::uuid,
        :'eventCanceledID'::uuid,
        :'eventDeletedStatusID'::uuid,
        :'eventRejectedID'::uuid,
        :'eventRemovedID'::uuid
    ],
    'Should order non-deleted events by start date descending'
);

-- Should paginate after ordering
select is(
    (
        select array_agg((item->>'event_id')::uuid order by ordinality)
        from jsonb_array_elements(list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":2,"offset":1}'::jsonb)::jsonb->'events')
            with ordinality as events(item, ordinality)
    ),
    array[:'eventApprovedID'::uuid, :'eventCanceledID'::uuid],
    'Should paginate after ordering'
);

-- Should report the total before pagination
select is(
    (list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":2,"offset":1}'::jsonb)::jsonb->>'total')::int,
    6,
    'Should report the total before pagination'
);

-- Should return invitation and response details for an approved event
select is(
    (
        select jsonb_build_object(
            'invitation_id', item->'invitation_id',
            'invited_at', item->'invited_at',
            'responded_at', item->'responded_at',
            'status', item->'status'
        )
        from jsonb_array_elements(list_group_cohosted_events(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb->'events') item
        where item->>'event_id' = :'eventApprovedID'
    ),
    jsonb_build_object(
        'invitation_id', :'eventApprovedInvitationID'::uuid,
        'invited_at', 1735689600,
        'responded_at', 1735776000,
        'status', 'approved'
    ),
    'Should return invitation and response details for an approved event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
