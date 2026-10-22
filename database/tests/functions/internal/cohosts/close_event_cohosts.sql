-- Tests closing event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedCancelGroupID 'e5040000-0000-0000-0000-000000000001'
\set approvedDeleteGroupID 'e5040000-0000-0000-0000-000000000002'
\set canceledUntouchedGroupID 'e5040000-0000-0000-0000-000000000003'
\set communityID 'e5040000-0000-0000-0000-000000000004'
\set deleteEventID 'e5040000-0000-0000-0000-000000000005'
\set eventCanceledDeleteGroupID 'e5040000-0000-0000-0000-000000000006'
\set eventCategoryID 'e5040000-0000-0000-0000-000000000007'
\set eventID 'e5040000-0000-0000-0000-000000000008'
\set groupCategoryID 'e5040000-0000-0000-0000-000000000009'
\set groupID 'e5040000-0000-0000-0000-00000000000a'
\set noChangeEventID 'e5040000-0000-0000-0000-00000000000b'
\set pendingCancelGroupID 'e5040000-0000-0000-0000-00000000000c'
\set pendingDeleteGroupID 'e5040000-0000-0000-0000-00000000000d'
\set rejectedUntouchedGroupID 'e5040000-0000-0000-0000-00000000000e'
\set removedUntouchedGroupID 'e5040000-0000-0000-0000-00000000000f'
\set unknownEventID 'e5040000-0000-0000-0000-000000000011'
\set userID 'e5040000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, owner group, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'deleteEventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 10));
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 7));
select fx_event(:'noChangeEventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 3));
select fx_user(:'userID');

-- Co-host groups
select fx_group(:'approvedCancelGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'approvedDeleteGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'canceledUntouchedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'eventCanceledDeleteGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingCancelGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingDeleteGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'rejectedUntouchedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'removedUntouchedGroupID', :'communityID', :'groupCategoryID');

-- Cancellation rows covering closable and untouched statuses
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'approvedCancelGroupID'),
    ('2025-01-01 00:00:00+00', 'canceled', :'eventID', :'canceledUntouchedGroupID'),
    (null, 'pending', :'eventID', :'pendingCancelGroupID'),
    (null, 'rejected', :'eventID', :'rejectedUntouchedGroupID'),
    ('2025-01-01 00:00:00+00', 'removed', :'eventID', :'removedUntouchedGroupID');

-- Deletion rows covering every closable status
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'deleteEventID', :'approvedDeleteGroupID'),
    ('2025-01-01 00:00:00+00', 'event-canceled', :'deleteEventID', :'eventCanceledDeleteGroupID'),
    (null, 'pending', :'deleteEventID', :'pendingDeleteGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject invalid close statuses with an internal error
select throws_ok(
    format('select close_event_cohosts(%L::uuid, %L::uuid, ''removed'')', :'userID', :'eventID'),
    'P0001',
    'invalid event co-host close status',
    'Should reject invalid close statuses with an internal error'
);

-- Should reject unknown events with an internal error
select throws_ok(
    format('select close_event_cohosts(%L::uuid, %L::uuid, ''event-canceled'')', :'userID', :'unknownEventID'),
    'P0001',
    'event not found',
    'Should reject unknown events with an internal error'
);

-- Should move pending and approved rows to event-canceled
select lives_ok(
    format('select close_event_cohosts(%L::uuid, %L::uuid, ''event-canceled'')', :'userID', :'eventID'),
    'Should move pending and approved rows to event-canceled'
);

-- Should keep approval evidence, record the responder and leave rejected, canceled, and removed rows untouched
select results_eq(
    format($$
        select group_id, event_cohost_status_id, approved_at, responded_at, responded_by
        from event_cohost
        where event_id = %L::uuid
        order by group_id
    $$, :'eventID'),
    format($$
        values
            (%L::uuid, 'event-canceled', '2025-01-01 00:00:00+00'::timestamptz, current_timestamp, %L::uuid),
            (%L::uuid, 'canceled', '2025-01-01 00:00:00+00'::timestamptz, null::timestamptz, null::uuid),
            (%L::uuid, 'event-canceled', null::timestamptz, current_timestamp, %L::uuid),
            (%L::uuid, 'rejected', null::timestamptz, null::timestamptz, null::uuid),
            (%L::uuid, 'removed', '2025-01-01 00:00:00+00'::timestamptz, null::timestamptz, null::uuid)
    $$,
        :'approvedCancelGroupID', :'userID',
        :'canceledUntouchedGroupID',
        :'pendingCancelGroupID', :'userID',
        :'rejectedUntouchedGroupID',
        :'removedUntouchedGroupID'
    ),
    'Should keep approval evidence, record the responder and leave rejected, canceled, and removed rows untouched'
);

-- Should increment revision when cancellation changes rows
select is((select cohosts_revision from event where event_id = :'eventID'), 8, 'Should increment revision when cancellation changes rows');

-- Should write actor audit rows for each changed cancellation row on both scopes
select results_eq(
    format($$
        select actor_user_id, (details->>'cohost_group_id')::uuid, details->>'from_status', group_id, details->>'to_status'
        from audit_log
        where action = 'event_cohost_closed'
        and event_id = %L::uuid
        order by 2, 4
    $$, :'eventID'),
    format($$
        values
            (%L::uuid, %L::uuid, 'approved', %L::uuid, 'event-canceled'),
            (%L::uuid, %L::uuid, 'approved', %L::uuid, 'event-canceled'),
            (%L::uuid, %L::uuid, 'pending', %L::uuid, 'event-canceled'),
            (%L::uuid, %L::uuid, 'pending', %L::uuid, 'event-canceled')
    $$,
        :'userID', :'approvedCancelGroupID', :'approvedCancelGroupID',
        :'userID', :'approvedCancelGroupID', :'groupID',
        :'userID', :'pendingCancelGroupID', :'groupID',
        :'userID', :'pendingCancelGroupID', :'pendingCancelGroupID'
    ),
    'Should write actor audit rows for each changed cancellation row on both scopes'
);

-- Should move pending, approved, and event-canceled rows to event-deleted
select lives_ok(
    format('select close_event_cohosts(%L::uuid, %L::uuid, ''event-deleted'')', :'userID', :'deleteEventID'),
    'Should move pending, approved, and event-canceled rows to event-deleted'
);

-- Should retain approval evidence and record the responder while deleting co-host rows
select results_eq(
    format($$
        select group_id, event_cohost_status_id, approved_at, responded_at, responded_by
        from event_cohost
        where event_id = %L::uuid
        order by group_id
    $$, :'deleteEventID'),
    format($$
        values
            (%L::uuid, 'event-deleted', '2025-01-01 00:00:00+00'::timestamptz, current_timestamp, %L::uuid),
            (%L::uuid, 'event-deleted', '2025-01-01 00:00:00+00'::timestamptz, current_timestamp, %L::uuid),
            (%L::uuid, 'event-deleted', null::timestamptz, current_timestamp, %L::uuid)
    $$,
        :'approvedDeleteGroupID', :'userID',
        :'eventCanceledDeleteGroupID', :'userID',
        :'pendingDeleteGroupID', :'userID'
    ),
    'Should retain approval evidence and record the responder while deleting co-host rows'
);

-- Should increment revision when deletion changes rows
select is((select cohosts_revision from event where event_id = :'deleteEventID'), 11, 'Should increment revision when deletion changes rows');

-- Should write actor audit rows for each changed deletion row on both scopes
select results_eq(
    format($$
        select actor_user_id, (details->>'cohost_group_id')::uuid, details->>'from_status', group_id, details->>'to_status'
        from audit_log
        where action = 'event_cohost_closed'
        and event_id = %L::uuid
        order by 2, 4
    $$, :'deleteEventID'),
    format($$
        values
            (%L::uuid, %L::uuid, 'approved', %L::uuid, 'event-deleted'),
            (%L::uuid, %L::uuid, 'approved', %L::uuid, 'event-deleted'),
            (%L::uuid, %L::uuid, 'event-canceled', %L::uuid, 'event-deleted'),
            (%L::uuid, %L::uuid, 'event-canceled', %L::uuid, 'event-deleted'),
            (%L::uuid, %L::uuid, 'pending', %L::uuid, 'event-deleted'),
            (%L::uuid, %L::uuid, 'pending', %L::uuid, 'event-deleted')
    $$,
        :'userID', :'approvedDeleteGroupID', :'approvedDeleteGroupID',
        :'userID', :'approvedDeleteGroupID', :'groupID',
        :'userID', :'eventCanceledDeleteGroupID', :'eventCanceledDeleteGroupID',
        :'userID', :'eventCanceledDeleteGroupID', :'groupID',
        :'userID', :'pendingDeleteGroupID', :'groupID',
        :'userID', :'pendingDeleteGroupID', :'pendingDeleteGroupID'
    ),
    'Should write actor audit rows for each changed deletion row on both scopes'
);

-- Should accept closing an event without closable co-hosts
select lives_ok(
    format('select close_event_cohosts(%L::uuid, %L::uuid, ''event-canceled'')', :'userID', :'noChangeEventID'),
    'Should accept closing an event without closable co-hosts'
);

-- Should not increment revision when no rows change
select is((select cohosts_revision from event where event_id = :'noChangeEventID'), 3, 'Should not increment revision when no rows change');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
