-- Tests locking events that accept enrollment transitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'f2020000-0000-0000-0000-000000000001'
\set communityID 'f2020000-0000-0000-0000-000000000002'
\set eventCategoryID 'f2020000-0000-0000-0000-000000000006'
\set groupCategoryID 'f2020000-0000-0000-0000-000000000007'
\set groupID 'f2020000-0000-0000-0000-000000000008'
\set liveEventID 'f2020000-0000-0000-0000-00000000000b'
\set otherCommunityID 'f2020000-0000-0000-0000-00000000000c'
\set otherGroupID 'f2020000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the events
select fx_community(:'communityID');

-- Community used by the cross-community scenario
select fx_community(:'otherCommunityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that owns the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group used by the cross-group scenario
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Canceled event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published upcoming event
select fx_event(:'liveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock the event row for update
-- Take the lock within this scenario before reading the row's xmax
select (lock_active_event(:'communityID', null, :'liveEventID')).event_id as "lockedEventID" \gset

select is(
    (select xmax::text from event where event_id = :'liveEventID'),
    (pg_current_xact_id()::text::bigint % 4294967296)::text,
    'Should lock the event row for update'
);

-- Should reject canceled events
select throws_ok(
    format($$select lock_active_event(%L::uuid, null, %L::uuid)$$, :'communityID', :'canceledEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject events from another community
select throws_ok(
    format($$select lock_active_event(%L::uuid, null, %L::uuid)$$, :'otherCommunityID', :'liveEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject events from another community'
);

-- Should reject events from another group
select throws_ok(
    format($$select lock_active_event(null, %L::uuid, %L::uuid)$$, :'otherGroupID', :'liveEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject events from another group'
);

-- Should require a scope
select throws_ok(
    format($$select lock_active_event(null, null, %L::uuid)$$, :'liveEventID'),
    'P0001',
    'lock_active_event requires a community or group scope',
    'Should require a scope'
);

-- Should return the event row when scoped by community
select is(
    (select (lock_active_event(:'communityID', null, :'liveEventID')).event_id),
    :'liveEventID'::uuid,
    'Should return the event row when scoped by community'
);

-- Should return the event row when scoped by group
select is(
    (select (lock_active_event(null, :'groupID', :'liveEventID')).group_id),
    :'groupID'::uuid,
    'Should return the event row when scoped by group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
