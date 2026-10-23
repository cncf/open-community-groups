-- Tests locking events that organizers can still manage.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID '10ce0000-0000-0000-0000-000000000001'
\set canceledEventID '10ce0000-0000-0000-0000-000000000002'
\set communityID '10ce0000-0000-0000-0000-000000000003'
\set deletedEventID '10ce0000-0000-0000-0000-000000000004'
\set eventCategoryID '10ce0000-0000-0000-0000-000000000005'
\set groupCategoryID '10ce0000-0000-0000-0000-000000000006'
\set groupID '10ce0000-0000-0000-0000-000000000007'
\set missingEventID '10ce0000-0000-0000-0000-000000000008'
\set otherGroupID '10ce0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the events
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that owns the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group used by the cross-group scenario
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Active published event
select fx_event(:'activeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Canceled event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Deleted event that was never canceled
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock the event row for update
-- Take the lock within this scenario before reading the row's xmax
select (lock_manageable_event(:'groupID', :'activeEventID', false)).event_id as "lockedEventID" \gset

select is(
    (select xmax::text from event where event_id = :'activeEventID'),
    (pg_current_xact_id()::text::bigint % 4294967296)::text,
    'Should lock the event row for update'
);

-- Should reject a canceled event when canceled events are not allowed
select throws_ok(
    format($$select lock_manageable_event(%L::uuid, %L::uuid, false)$$, :'groupID', :'canceledEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject a canceled event when canceled events are not allowed'
);

-- Should reject a deleted event when canceled events are allowed
select throws_ok(
    format($$select lock_manageable_event(%L::uuid, %L::uuid, true)$$, :'groupID', :'deletedEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject a deleted event when canceled events are allowed'
);

-- Should reject a deleted event when canceled events are not allowed
select throws_ok(
    format($$select lock_manageable_event(%L::uuid, %L::uuid, false)$$, :'groupID', :'deletedEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject a deleted event when canceled events are not allowed'
);

-- Should reject a missing event
select throws_ok(
    format($$select lock_manageable_event(%L::uuid, %L::uuid, true)$$, :'groupID', :'missingEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject a missing event'
);

-- Should reject an event owned by another group
select throws_ok(
    format($$select lock_manageable_event(%L::uuid, %L::uuid, true)$$, :'otherGroupID', :'activeEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject an event owned by another group'
);

-- Should return a canceled event when canceled events are allowed
select results_eq(
    format(
        $$select event_id, canceled from lock_manageable_event(%L::uuid, %L::uuid, true)$$,
        :'groupID',
        :'canceledEventID'
    ),
    format($$values (%L::uuid, true)$$, :'canceledEventID'),
    'Should return a canceled event when canceled events are allowed'
);

-- Should return an active event when canceled events are allowed
select results_eq(
    format(
        $$select event_id, canceled from lock_manageable_event(%L::uuid, %L::uuid, true)$$,
        :'groupID',
        :'activeEventID'
    ),
    format($$values (%L::uuid, false)$$, :'activeEventID'),
    'Should return an active event when canceled events are allowed'
);

-- Should return an active event when canceled events are not allowed
select results_eq(
    format(
        $$select event_id, canceled from lock_manageable_event(%L::uuid, %L::uuid, false)$$,
        :'groupID',
        :'activeEventID'
    ),
    format($$values (%L::uuid, false)$$, :'activeEventID'),
    'Should return an active event when canceled events are not allowed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
