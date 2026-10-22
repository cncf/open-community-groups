-- Tests locking an event whose surveys organizers can manage.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'a5e00003-0000-0000-0000-000000000001'
\set communityID 'a5e00003-0000-0000-0000-000000000002'
\set deletedEventID 'a5e00003-0000-0000-0000-000000000003'
\set deletedGroupEventID 'a5e00003-0000-0000-0000-000000000004'
\set deletedGroupID 'a5e00003-0000-0000-0000-000000000005'
\set draftEventID 'a5e00003-0000-0000-0000-000000000006'
\set endedEventID 'a5e00003-0000-0000-0000-000000000007'
\set eventCategoryID 'a5e00003-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e00003-0000-0000-0000-000000000009'
\set groupID 'a5e00003-0000-0000-0000-00000000000a'
\set inactiveGroupEventID 'a5e00003-0000-0000-0000-00000000000b'
\set inactiveGroupID 'a5e00003-0000-0000-0000-00000000000c'
\set missingEventID 'a5e00003-0000-0000-0000-00000000000d'
\set otherGroupID 'a5e00003-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Deleted group whose events cannot be managed
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Active group whose events are managed
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Inactive group whose events cannot be managed
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false
));

-- Other active group used for cross-group requests
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Canceled event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp - interval '1 day'
));

-- Deleted event
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'starts_at', current_timestamp - interval '1 day'
));

-- Event in the deleted group
select fx_event(:'deletedGroupEventID', :'deletedGroupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp - interval '1 day'
));

-- Unpublished upcoming event
select fx_event(:'draftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event that already ended
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 hour',
    'published', true,
    'starts_at', current_timestamp - interval '2 hours'
));

-- Event in the inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp - interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow events that already ended
select is(
    (select (lock_event_for_surveys(:'groupID', :'endedEventID')).event_id),
    :'endedEventID'::uuid,
    'Should allow events that already ended'
);

-- Should lock the event row for update
-- Relies on the lock taken by the ended event scenario above
select is(
    (select xmax::text from event where event_id = :'endedEventID'),
    (pg_current_xact_id()::text::bigint % 4294967296)::text,
    'Should lock the event row for update'
);

-- Should reject canceled events
select throws_ok(
    format($$select lock_event_for_surveys(%L::uuid, %L::uuid)$$, :'groupID', :'canceledEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject deleted events
select throws_ok(
    format($$select lock_event_for_surveys(%L::uuid, %L::uuid)$$, :'groupID', :'deletedEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject deleted events'
);

-- Should reject events from another group
select throws_ok(
    format($$select lock_event_for_surveys(%L::uuid, %L::uuid)$$, :'otherGroupID', :'endedEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject events from another group'
);

-- Should reject events whose group is deleted
select throws_ok(
    format(
        $$select lock_event_for_surveys(%L::uuid, %L::uuid)$$,
        :'deletedGroupID',
        :'deletedGroupEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events whose group is deleted'
);

-- Should reject events whose group is inactive
select throws_ok(
    format(
        $$select lock_event_for_surveys(%L::uuid, %L::uuid)$$,
        :'inactiveGroupID',
        :'inactiveGroupEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events whose group is inactive'
);

-- Should reject missing events
select throws_ok(
    format($$select lock_event_for_surveys(%L::uuid, %L::uuid)$$, :'groupID', :'missingEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject missing events'
);

-- Should return unpublished events
select is(
    (select (lock_event_for_surveys(:'groupID', :'draftEventID')).published),
    false,
    'Should return unpublished events'
);

-- Should return upcoming events
select is(
    (select (lock_event_for_surveys(:'groupID', :'draftEventID')).event_id),
    :'draftEventID'::uuid,
    'Should return upcoming events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
