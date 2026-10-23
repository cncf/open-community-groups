-- Tests locking the ticket tiers of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '10cc0000-0000-0000-0000-000000000001'
\set emptyEventID '10cc0000-0000-0000-0000-000000000002'
\set eventCategoryID '10cc0000-0000-0000-0000-000000000003'
\set eventID '10cc0000-0000-0000-0000-000000000004'
\set firstTicketTypeID '10cc0000-0000-0000-0000-000000000005'
\set groupCategoryID '10cc0000-0000-0000-0000-000000000006'
\set groupID '10cc0000-0000-0000-0000-000000000007'
\set otherEventID '10cc0000-0000-0000-0000-000000000008'
\set otherTicketTypeID '10cc0000-0000-0000-0000-000000000009'
\set secondTicketTypeID '10cc0000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the events
select fx_community(:'communityID');

-- Event category used by the events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event without ticket tiers
select fx_event(:'emptyEventID', :'groupID', :'eventCategoryID');

-- Event whose ticket tiers are locked
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event whose ticket tier stays unlocked
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- First ticket tier of the locked event
select fx_event_ticket_type(:'firstTicketTypeID', :'eventID');

-- Ticket tier of the other event
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID');

-- Second ticket tier of the locked event
select fx_event_ticket_type(:'secondTicketTypeID', :'eventID', jsonb_build_object('order', 2));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should leave the ticket tiers of other events unlocked
-- Take the lock within this scenario before reading the tiers' xmax
select 1 as "eventTiersLocked" from lock_event_ticket_types(:'eventID') \gset

select is(
    (select xmax::text from event_ticket_type where event_ticket_type_id = :'otherTicketTypeID'),
    '0',
    'Should leave the ticket tiers of other events unlocked'
);

-- Should lock every ticket tier of the event for update
-- Take the lock within this scenario before reading the tiers' xmax
select 1 as "eventLocked" from lock_event_ticket_types(:'eventID') \gset

select is(
    (
        select bool_and(xmax::text = (pg_current_xact_id()::text::bigint % 4294967296)::text)
        from event_ticket_type
        where event_id = :'eventID'
    ),
    true,
    'Should lock every ticket tier of the event for update'
);

-- Should succeed for an event without ticket tiers
select lives_ok(
    format($$select lock_event_ticket_types(%L::uuid)$$, :'emptyEventID'),
    'Should succeed for an event without ticket tiers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
