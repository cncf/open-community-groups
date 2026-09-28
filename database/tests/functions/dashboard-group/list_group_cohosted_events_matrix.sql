-- Tests list_group_cohosted_events statuses, pagination, ordering, and deleted-event exclusion.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5190000-0000-0000-0000-000000000001'
\set communityID 'e5190000-0000-0000-0000-000000000002'
\set deletedEventID 'e5190000-0000-0000-0000-000000000003'
\set eventApprovedID 'e5190000-0000-0000-0000-000000000004'
\set eventCanceledID 'e5190000-0000-0000-0000-000000000005'
\set eventCategoryID 'e5190000-0000-0000-0000-000000000006'
\set eventDeletedStatusID 'e5190000-0000-0000-0000-000000000007'
\set eventPendingID 'e5190000-0000-0000-0000-000000000008'
\set eventRejectedID 'e5190000-0000-0000-0000-000000000009'
\set eventRemovedID 'e5190000-0000-0000-0000-00000000000a'
\set groupCategoryID 'e5190000-0000-0000-0000-00000000000b'
\set ownerGroupID 'e5190000-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID', jsonb_build_object('display_name', 'Hosted Events Matrix', 'name', 'hosted-events-matrix'));
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

-- Co-host rows covering every list status and deleted-event exclusion
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invited_at, responded_at) values
    (current_timestamp, 'approved', :'deletedEventID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-02 00:00:00+00'),
    (current_timestamp, 'approved', :'eventApprovedID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-02 00:00:00+00'),
    (current_timestamp, 'canceled', :'eventCanceledID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-03 00:00:00+00'),
    (current_timestamp, 'event-deleted', :'eventDeletedStatusID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-04 00:00:00+00'),
    (null, 'pending', :'eventPendingID', :'cohostGroupID', '2025-01-01 00:00:00+00', null),
    (null, 'rejected', :'eventRejectedID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-05 00:00:00+00'),
    (current_timestamp, 'removed', :'eventRemovedID', :'cohostGroupID', '2025-01-01 00:00:00+00', '2025-01-06 00:00:00+00');

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

-- Should exclude deleted events from the list
select ok(
    not list_group_cohosted_events(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb @> format('{"events":[{"event_id":"%s"}]}', :'deletedEventID')::jsonb,
    'Should exclude deleted events from the list'
);

-- Should order by starts_at descending
select is(
    (
        select jsonb_agg(item->>'event_id')
        from jsonb_array_elements(list_group_cohosted_events(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb->'events') item
        limit 2
    )->0,
    to_jsonb(:'eventPendingID'::text),
    'Should order by starts_at descending'
);

-- Should paginate after ordering
select is(
    jsonb_array_length(list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":2,"offset":1}'::jsonb)::jsonb->'events'),
    2,
    'Should paginate after ordering'
);

-- Should include optional and timestamp fields without sensitive internals
select ok(
    (list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":1}'::jsonb)::jsonb->'events'->0)
        ?& array['event_id', 'event_kind', 'event_logo_url', 'invitation_id', 'invited_at', 'owner_group_slug_pretty', 'starts_at', 'timezone']
    and not ((list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":1}'::jsonb)::jsonb->'events'->0) ? 'meeting_join_url'),
    'Should include optional and timestamp fields without sensitive internals'
);

-- Should report the total before pagination
select is(
    (list_group_cohosted_events(:'cohostGroupID'::uuid, '{"limit":2,"offset":1}'::jsonb)::jsonb->>'total')::int,
    6,
    'Should report the total before pagination'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
